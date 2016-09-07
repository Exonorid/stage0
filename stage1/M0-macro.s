:start
	;; We will be using R13 for storage of Head
	;; We will be using R14 for our condition codes
	LOADUI R15 $stack           ; Put stack at end of program

	;; Main program
	;; Reads contents of Tape_01 and applies all Definitions
	;; Writes results to Tape_02
;; Accepts no arguments and HALTS when done
:main
	;; Prep TAPE_01
	LOADUI R0 0x1100
	FOPEN_READ

	FALSE R0                    ; Head is NULL
	LOADUI R0 0x1100            ; Read Tape_01
	FALSE R14                   ; We haven't yet reached EOF
:main_0
	CALLI R15 @Tokenize_Line    ; Call Tokenize_Line
	JUMP.Z R14 @main_0          ; Until we reach EOF

	;; Done reading File
	LOADUI R0 0x1100            ; Close TAPE_01
	FCLOSE


	CALLI R15 @Identify_Macros  ; Tag all nodes that are macros
	CALLI R15 @Line_Macro       ; Apply macros down nodes
	CALLI R15 @Process_String   ; Convert string values to Hex16
	CALLI R15 @Eval_Immediates  ; Convert numbers to hex
	CALLI R15 @Preserve_Other   ; Ensure labels/Pointers aren't lost
	CALLI R15 @Print_Hex        ; Write Nodes to Tape_02
	HALT                        ; We are Done


;; Primative malloc function
;; Recieves number of bytes to allocate in R0
;; Returns pointer to block of that size in R0
;; Returns to whatever called it
:malloc
	;; Preserve registers
	PUSHR R1 R15
	;; Get current malloc pointer
	LOADR R1 @malloc_pointer
	;; Deal with special case
	CMPSKIP.NE R1 0             ; If Zero set to our start of heap space
	LOADUI R1 0x4000

	;; update malloc pointer
	SWAP R0 R1
	ADD R1 R0 R1
	STORER R1 @malloc_pointer

;; Done
	;; Restore registers
	POPR R1 R15
	RET R15
;; Our static value for malloc pointer
:malloc_pointer
	NOP


	;; Tokenize_Line function
	;; Recieves pointer to Head in R0 and desired input in R1
	;; Alters R14 when EOF Reached
	;; Returns to whatever called it
:Tokenize_Line
	;; Preserve registers
	PUSHR R0 R15
	PUSHR R1 R15
	PUSHR R2 R15
	PUSHR R3 R15
	PUSHR R4 R15

	;; Initialize
	MOVE R4 R0                  ; Get Head pointer out of the way
:Tokenize_Line_0
	FGETC                       ; Get a Char

	;; Deal with lines comments starting with #
	CMPSKIP.NE R0 35
	JUMP @Purge_Line_Comment

	;; Deal with Line comments starting with ;
	CMPSKIP.NE R0 59
	JUMP @Purge_Line_Comment

	;; Deal with Tab
	CMPSKIP.NE R0 9
	JUMP @Tokenize_Line_0       ; Throw away byte and try again

	;; Deal with New line
	CMPSKIP.NE R0 10
	JUMP @Tokenize_Line_0       ; Throw away byte and try again

	;; Deal with space characters
	CMPSKIP.NE R0 32
	JUMP @Tokenize_Line_0       ; Throw away byte and try again

	;; Flag if reached EOF
	CMPSKIP.GE R0 0
	TRUE R14

	;; Stop if EOF
	CMPSKIP.GE R0 0
	JUMP @Tokenize_Line_Done

	;; Allocate a new Node
	MOVE R2 R0                  ; Get Char out the way
	LOADUI R0 16                ; Allocate 16 Bytes
	CALLI R15 @malloc           ; Get address of new Node
	SWAP R2 R0                  ; Store Pointer in R2

	;; Deal with Strings wrapped in "
	CMPSKIP.NE R0 34
	JUMP @Store_String

	;; Deal with Strings wrapped in '
	CMPSKIP.NE R0 39
	JUMP @Store_String

	;; Everything else is an atom store it
	CALLI R15 @Store_Atom

:Tokenize_Line_Done
	CALLI R15 @Add_Token        ; Append new token to Head

	;; Restore registers
	POPR R4 R15
	POPR R3 R15
	POPR R2 R15
	POPR R1 R15
	POPR R0 R15

	;; Return since we are done
	RET R15


;; Purge_Line_Comment Function
;; Recieves char in R0 and desired input in R1
;; Modifies R0
;; Returns to Tokenize_Line as if the entire line
;; Comment never existed
:Purge_Line_Comment
	FGETC                       ; Get another Char
	CMPSKIP.E R0 10             ; Stop When LF is reached
	JUMP @Purge_Line_Comment    ; Otherwise keep looping
	JUMP @Tokenize_Line_0       ; Return as if this never happened


;; Store_String function
;; Recieves Char in R0, desired input in R1
;; And node pointer in R2
;; Modifies node Text to point to string and sets
;; Type to string.
:Store_String
	;; Preserve registers
	PUSHR R4 R15
	PUSHR R5 R15
	PUSHR R6 R15

	;; Initialize
	MOVE R6 R0                  ; Get R0 out of the way
	CALLI R15 @malloc           ; Get where space is free
	MOVE R4 R0                  ; Put pointer someplace safe
	FALSE R5                    ; Start at index 0
	COPY R0 R6                  ; Copy Char back into R0

	;; Primary Loop
:Store_String_0
	STOREX8 R0 R4 R5            ; Store the Byte
	FGETC                       ; Get next Byte
	ADDUI R5 R5 1               ; Prep for next loop
	CMPJUMP.NE R0 R6 @Store_String_0 ; Loop if matching not found

	;; Clean up
	STORE32 R4 R2 8             ; Set Text pointer
	MOVE R0 R5                  ; Correct Malloc
	CALLI R15 @malloc           ; To the amount of space used
	LOADUI R0 2                 ; Using type string
	STORE32 R0 R2 4             ; Set node type

	;; Restore Registers
	POPR R6 R15
	POPR R5 R15
	POPR R4 R15
	JUMP @Tokenize_Line_Done


;; Store_Atom function
;; Recieves Char in R0, desired input in R1
;; And node pointer in R2
;; Modifies node Text to point to string
:Store_Atom
	;; Preserve registers
	PUSHR R4 R15
	PUSHR R5 R15

	;; Initialize
	MOVE R5 R0                  ; Get R0 out of the way
	CALLI R15 @malloc           ; Get where space is free
	MOVE R4 R0                  ; Put pointer someplace safe
	MOVE R0 R5                  ; Copy Char back and Set index to 0

	;; Primary Loop
:Store_Atom_0
	STOREX8 R0 R4 R5            ; Store the Byte
	FGETC                       ; Get next Byte
	ADDUI R5 R5 1               ; Prep for next loop

	CMPSKIP.NE R0 9             ; If char is Tab
	JUMP @Store_Atom_Done       ; Be done

	CMPSKIP.NE R0 10            ; If char is LF
	JUMP @Store_Atom_Done       ; Be done

	CMPSKIP.NE R0 32            ; If char is Space
	JUMP @Store_Atom_Done       ; Be done

	;; Otherwise loop
	JUMP @Store_Atom_0

:Store_Atom_Done
	;; Cleanup
	STORE32 R4 R2 8             ; Set Text pointer
	MOVE R0 R5                  ; Correct Malloc
	CALLI R15 @malloc           ; To the amount of space used

	;; Restore Registers
	POPR R5 R15
	POPR R4 R15
	RET R15


	;; Add_Token Function
	;; Recieves pointers in R0 R1
	;; Alters R0 if NULL
	;; Appends nodes together
	;; Returns to whatever called it
:Add_Token
		;; Preserve Registers
	PUSHR R2 R15
	PUSHR R1 R15
	PUSHR R0 R15

	;; Handle if Head is NULL
	JUMP.NZ R0 @Add_Token_0
	POPR R0 R15
	PUSHR R1 R15
	JUMP @Add_Token_2

:Add_Token_0
	;; Handle if Head->next is NULL
	LOAD32 R2 R0 0
	JUMP.NZ R2 @Add_Token_1
	;; Set head->next = p
	STORE32 R1 R0 0
	JUMP @Add_Token_2

:Add_Token_1
	;; Handle case of Head->next not being NULL
	LOAD32 R0 R0 0              ; Move to next node
	LOAD32 R2 R0 0              ; Get node->next
	CMPSKIP.E R2 0              ; If it is not null
	JUMP @Add_Token_1           ; Move to the next node and try again
	JUMP @Add_Token_0           ; Else simply act as if we got this node
	                            ; in the first place

:Add_Token_2
	;; Restore registers
	POPR R0 R15
	POPR R1 R15
	POPR R2 R15
	RET R15

;; strcmp function
;; Recieves pointers to null terminated strings
;; In R0 and R1
;; Returns if they are equal in R0
;; Returns to whatever called it
:strcmp
	;; Preserve registers
	PUSHR R2 R15
	PUSHR R3 R15
	PUSHR R4 R15
	;; Setup registers
	MOVE R2 R0                  ; Put R0 in a safe place
	MOVE R3 R1                  ; Put R1 in a safe place
	LOADUI R4 0                 ; Starting at index 0
:cmpbyte
	LOADXU8 R0 R2 R4            ; Get a byte of our first string
	LOADXU8 R1 R3 R4            ; Get a byte of our second string
	ADDUI R4 R4 1               ; Prep for next loop
	CMP R1 R0 R1                ; Compare the bytes
	CMPSKIP.E R0 0              ; Stop if byte is NULL
	JUMP.E R1 @cmpbyte          ; Loop if bytes are equal
;; Done
	MOVE R0 R1                  ; Prepare for return
	;; Restore registers
	POPR R4 R15
	POPR R3 R15
	POPR R2 R15
	RET R15


;; Identify_Macros Function
;; Recieves a pointer to a node in R0
;; If the text stored in its Text segment matches
;; DEFINE, flag it and its next two nodes as macro
;; Loop until all nodes are checked
;; Return to whatever called it
:Identify_Macros
	;; Preserve Registers
	PUSHR R0 R15
	PUSHR R1 R15
	PUSHR R2 R15

	;; Main Loop
:Identify_Macros_0
	MOVE R1 R0
	LOADUI R0 $Identify_Macros_string
	CALLI R15 @strcmp
	JUMP.NE R0 @Identify_Macros_1

	;; It is a definition
	;; Set p->Type = macro
	LOADUI R0 1                 ; The Enum value for macro
	STORE32 R0 R1 4             ; Set node type

	;; Set p->Text = p->Next->Text
	LOAD32 R2 R1 0              ; Get Next
	LOAD32 R0 R2 8              ; Get Next->Text
	STORE32 R0 R1 8             ; Set Text = Next->Text

	;; Set p->Expression = p->next->next->Text
	LOAD32 R2 R2 0              ; Get Next->Next
	LOAD32 R0 R2 8              ; Get Next->Next->Text
	STORE32 R0 R1 12            ; Set Expression = Next->Next->Text

	;; Set p->Next = p->Next->Next->Next
	LOAD32 R0 R2 0              ; Get Next->Next->Next
	STORE32 R0 R1 0             ; Set Next = Next->Next->Next

:Identify_Macros_1
	LOAD32 R0 R1 0              ; Get node->next
	CMPSKIP.NE R0 0             ; If node->next is NULL
	JUMP @Identify_Macros_Done  ; Be done

	;; Otherwise keep looping
	JUMP @Identify_Macros_0

:Identify_Macros_Done
	;; Restore registers
	POPR R2 R15
	POPR R1 R15
	POPR R0 R15
	RET R15

:Identify_Macros_string
"DEFINE"


	;; Line_Macro Function
	;; Recieves a node pointer in R0
	;; Causes macros to be applied
	;; Returns to whatever called it
:Line_Macro
	;; Preserve Registers
	PUSHR R0 R15
	PUSHR R1 R15
	PUSHR R2 R15
	PUSHR R3 R15

	;; Main loop
:Line_Macro_0
	LOAD32 R3 R0 4              ; Load Node type
	LOAD32 R2 R0 12             ; Load Expression pointer
	LOAD32 R1 R0 8              ; Load Text pointer
	LOAD32 R0 R0 0              ; Load Next pointer
	CMPSKIP.NE R3 1             ; If a macro
	CALLI R15 @setExpression    ; Apply to other nodes
	CMPSKIP.E R0 0              ; If Next is Null
	JUMP @Line_Macro_0          ; Don't loop

	;; Clean up
	POPR R3 R15
	POPR R2 R15
	POPR R1 R15
	POPR R0 R15
	RET R15


;; setExpression Function
;; Recieves a node pointer in R0
;; A string pointer to compare against in R1
;; A string pointer for replacement in R2
;; Doesn't modify any registers
;; Returns to whatever called it
:setExpression
	;; Preserve registers
	PUSHR R0 R15
	PUSHR R3 R15

	LOAD32 R3 R0 0              ; Load Next
	SWAP R0 R3                  ; Protect R0
	CMPSKIP.E R0 0              ; if Next is Null
	CALLI R15 @setExpression    ; Don't recurse
	MOVE R0 R3                  ; Restore R0
	LOAD32 R3 R0 4              ; Load type into R3
	CMPSKIP.NE R3 1             ; If Node is a macro
	JUMP @setExpression_Done    ; Be done
	LOAD32 R3 R0 8              ; Load Text into R3
	SWAP R0 R3                  ; Prepare for strncmp
	CALLI R15 @strcmp           ; compare Text and Macro Text
	JUMP.NE R0 @setExpression_Done

	;; Node matches
	STORE32 R2 R3 12            ; Set node->Expression = Exp

:setExpression_Done
	;; Restore registers
	POPR R3 R15
	POPR R0 R15
	RET R15


;; Process_String Function
;; Recieves a Node in R0
;; Doesn't modify registers
;; Returns back to whatever called it
:Process_String
	;; Preserve Registers
	PUSHR R0 R15
	PUSHR R1 R15
	PUSHR R2 R15

	;; Get node type
	LOAD32 R1 R0 4              ; Load Type
	CMPSKIP.E R1 2              ; If not a string
	JUMP @Process_String_Done   ; Just go to next

	;; Its a string
	LOAD32 R1 R0 8              ; Get Text pointer
	LOAD32 R2 R1 0              ; Get first char of Text

	;; Deal with '
	CMPSKIP.E R2 39             ; If char is not '
	JUMP @Process_String_0      ; Move to next label

	;; Simply use Hex strings as is
	ADDUI R1 R1 1               ; Move Text pointer by 1
	STORE32 R1 R0 12            ; Set expression to Text + 1
	JUMP @Process_String_Done   ; And move on

:Process_String_0
	;; Deal with "
	CALLI R15 Hexify_String

:Process_String_Done
	LOAD32 R0 R0 0				; Load Next
	CMPSKIP.E R0 0				; If Next isn't NULL
	CALLI R15 @Process_String	; Recurse down list

	;; Restore registers
	POPR R2 R15
	POPR R1 R15
	POPR R0 R15
	RET R15


;; Where we are putting the start of our stack
:stack
