;;
;; Piotr K. Wyrwas' "The Mistake"
;; A game of pong, implemented entirely
;; in the x86 assembly language (64-bit)
;;

%include "extref.asm"

section .data
	;; Tells the API to init the video and event modules
	IFLAG_VIDEO:	equ 0x00000020
	IFLAG_EVENT:	equ 0x00004000
	IFLAG_FINAL:	equ IFLAG_VIDEO | IFLAG_EVENT

	;; SDL Quit event
	EVT_QUIT:	equ 0x100

	;; Tells the API to put the window at the center of the screen
	FLAG_CENTER:	equ 0x2FFF0000	

	;; Window dimensions (in pixels)
	WIDTH:		equ 1000
	HEIGHT:		equ 700

	;; Reserve some memory for SDL struct pointers
	;; QWords, 32-bit/e
	WINDOW:		dq 0
	RENDERER:	dq 0

	;; Window title
	TITLE:		db "Pong", 0

	;; Generic SDL error format
	GSDLF:		db "SDL Error: %s", 10, 0

	;; Specifis SDL errors
	INITF:		db "Error: Failed to initialize SDL.", 10, 0
	WINDOWF:	db "Error: Failed to create a window.", 10, 0
	RENDERF:	db "Error: Failed to create a renderer.", 10, 0

	;; Debug messages
	DINIT:		db "Debug: SDL Initialized.", 10, 0
	DWINDOW:	db "Debug: Window created.", 10, 0
	DRENDER:	db "Debug: Renderer created.", 10, 0

	;; SDL error string pointer
	SDL_SPTR:	dq 0

	;; Offset from the event pointer to the event type
	EVTT_OFF:	equ 0

	;; Background color information (black)
	BACKGROUND:
		db 0
		db 0
		db 0
		db 255

	;; Foreground color (white)
	FOREGROUND:
		db 255
		db 255
		db 255
		db 255

	PW:	equ 20
	PH:	equ 100
	YORG:	equ HEIGHT / 2 - PH / 2

	LPX:	dd 0
	LPY:	dd 520

	RPX:	dd WIDTH - PW
	RPY:	dd 350

	BS:	equ 10
	XB:	dd WIDTH / 2 - BS / 2
	YB:	dd HEIGHT / 2 - BS / 2

	VELX:	dd -1
	VELY:	dd 1

section .bss
	;; Reserve some memory for the SDL_Event struct
	EVENT:		resb 60

	;; Rectangle (used for drawing the paddles)
	RECT:		resb 16

section .text
	global main

	;; Expects pointer to error string in RAX
	handle_err:
		
		;; Set up the stack frame to avoid messing up
		;; the stack structure
		push rbp
		mov rbp, rsp

		;; Print the specific error message
		;; Also ensure, that the following register is cleared [just to avoid
		;; any weird behaviour resulting from passing additional values for
		;; placeholders, which were not mentioned in the format string in the first place]
		xor rsi, rsi
		call printf

		;; Get the SDL error for more information
		call SDL_GetError
		mov qword [SDL_SPTR], rax

		lea rdi, GSDLF
		mov rsi, [SDL_SPTR]
		call printf

	clean_exit:
		push rbp
		mov rbp, rsp

		;; Destroy (clean the memory after) the window
		cmp qword [WINDOW], 0
		je .skip_window

		mov rdi, [WINDOW]
		call SDL_DestroyWindow

		;; Dispose the renderer
		.skip_window:
		cmp qword [RENDERER], 0
		je .exit

		mov rdi, [RENDERER]
		call SDL_DestroyRenderer

		;; Exit the program using a glibc call
		.exit:
		mov rdi, 0
		call exit

	collide:
		;; New stack frame
		push rbp
		mov rbp, rsp

		;; Max Y-axis (bottom edge)
		cmp dword [YB], HEIGHT
		jl .cmp_minx

		mov eax, -1
		imul dword [VELY]
		mov dword [VELY], eax

		;; Min Y-axis (top edge)
		.cmp_minx:
		cmp dword [YB], 0
		jg .cmp_lpad

		mov eax, -1
		imul dword [VELY]
		mov dword [VELY], eax

		;; Left paddle
		.cmp_lpad:

		;; Check X (L)
		cmp dword [XB], PW
		jg .cmp_rpad

		;; Check x cutoff (L)
		cmp dword [XB], 0
		jle .cmp_rpad

		;; Check Min Y (L)
		mov eax, dword [YB]
		mov ebx, dword [LPY]
		cmp eax, ebx
		jl .cmp_rpad

		;; Check Max Y (L)
		mov eax, dword [YB]

		mov ebx, dword [LPY]
		add ebx, PH
		cmp eax, ebx
		jg .cmp_rpad

		;; Collision with the left paddle was detected.
		;; Change the velocity accordingly
		mov eax, -1
		imul dword [VELX]
		mov dword [VELX], eax

		;; Right paddle
		.cmp_rpad:
		
		;; Check X (R)
		mov eax, [RPX]
		cmp dword [XB], eax
		jl .end

		;; X Cutoff (R)
		cmp dword [XB], WIDTH
		jge .end

		;; Check min Y (R)
		mov eax, dword [YB]
		mov ebx, dword [RPY]
		cmp eax, ebx
		jl .end

		;; Check Max Y (R)
		mov eax, dword [YB]

		mov ebx, dword [RPY]
		add ebx, PH
		cmp eax, ebx
		jg .end

		;; Collision with the right paddle detected.
		;; Change the X direction (velocity, same as above)
		mov eax, -1
		imul dword [VELX]
		mov dword [VELX], eax

		.end:

		;; Destroy current stack frame
		mov rsp, rbp
		pop rbp

		ret

	bapplyvel:
		;: Do I still have to explain this?
		push rbp
		mov rbp, rsp

		;; The X-axis
		mov eax, [XB]
		mov ebx, [VELX]
		add eax, ebx

		mov [XB], eax

		;; Similarly, the Y-axis
		mov eax, [YB]
		mov ebx, [VELY]
		add eax, ebx

		mov [YB], eax

		mov rsp, rbp
		pop rbp

		ret

	setcolor:
		;; Set up the stack frame
		push rbp
		mov rbp, rsp

		mov rdi, [RENDERER]

		;; Access the red channel
		mov rsi, [rax]
		
		;; Green
		lea rbx, [rax + 1]
		mov rdx, [rbx]

		;; Blue
		lea rbx, [rax + 2]
		mov rcx, [rbx]

		;; Alpha / Transparency
		lea rbx, [rax + 3]
		mov r8, [rbx]

		;; Set the color
		call SDL_SetRenderDrawColor

		;; We'll ignore any errors this time

		;; Clear the stack frame
		mov rsp, rbp
		pop rbp

		ret

	;; edi - X, esi  - Y, edx - W, ecx - H
	updatep:
		;; The stack frame again
		push rbp
		mov rbp, rsp

		;; Update the X and Y coordinates
		mov dword [RECT], edi
		mov dword [RECT + 4], esi
		mov dword [RECT + 8], edx
		mov dword [RECT + 12], ecx

		;; Leave the stack frame
		mov rsp, rbp
		pop rbp

		ret

	drawall:
		;; Create a new stack frame
		push rbp
		mov rbp, rsp

		;; Set the background color
		lea rax, BACKGROUND
		call setcolor

		;; Clear the screen
		mov rdi, [RENDERER]
		call SDL_RenderClear	

		;; Choose the foreground color
		lea rax, FOREGROUND
		call setcolor

		;; Update the parameters of the left paddle and
		;; draw it to the screen.
		mov edi, [LPX]
		mov esi, [LPY]
		mov edx, PW
		mov ecx, PH
		call updatep

		mov rdi, [RENDERER]
		lea rsi, RECT
		call SDL_RenderFillRect

		;; Do the same things for the right paddle
		mov edi, [RPX]
		mov esi, [RPY]
		mov edx, PW
		mov ecx, PH
		call updatep

		mov rdi, [RENDERER]
		lea rsi, RECT
		call SDL_RenderFillRect

		;; And for the "ball" as well (Yes, it's a square)
		mov edi, [XB]
		mov esi, [YB]
		mov edx, BS
		mov ecx, BS
		call updatep

		mov rdi, [RENDERER]
		lea rsi, RECT
		call SDL_RenderFillRect

		;; Commit all changes to the screen buffer
		mov rdi, [RENDERER]
		call SDL_RenderPresent

		;; Return to the old frame
		mov rsp, rbp
		pop rbp

		ret

	main:
		;; Set up the stack frame
		push rbp
		mov rbp, rsp

		;; Clear the fields for the error handling function
		;; to behave properly.
		mov qword [WINDOW],   0
		mov qword [RENDERER], 0

		;; Initialize SDL
		mov rdi, IFLAG_FINAL
		call SDL_Init

		;; Handle any errors
		cmp rax, 0
		je .create_window

		;; Print the error message
		lea rdi, INITF
		call handle_err

		.create_window:

		;; Print a debug message
		lea rdi, DINIT
		call printf

		;; Create a window (see signature below)
		;; SDL_CreateWindow(title, x, y, width, height, flags)
		lea rdi, TITLE
		mov rsi, FLAG_CENTER
		mov rdx, FLAG_CENTER
		mov rcx, WIDTH
		mov r8,  HEIGHT
		mov r9,  0
		call SDL_CreateWindow

		;; Handle errors
		cmp rax, 0
		jne .create_renderer

		;; Print the error message
		lea rdi, WINDOWF
		call handle_err
		
		.create_renderer:

		;; Save the window pointer to memory
		mov qword [WINDOW], rax

		;; Print a debug message
		lea rdi, DWINDOW
		call printf

		;; Clear the registers used in the previous call
		;; to keep weird things from happening later on
		xor rdi, rdi
		xor rsi, rsi
		xor rdx, rdx
		xor rcx, rcx
		xor r8, r8
		xor r9, r9

		;; Create a renderer
		mov rdi, [WINDOW]
		mov rsi, -1
		mov rdx, 0
		call SDL_CreateRenderer

		;; Handle any errors
		cmp rax, 0
		jne .pre_main_loop

		lea rdi, RENDERF
		call handle_err

		;; Enter the main event and rendering loop
		.pre_main_loop:

		;; Save the renderer pointer to memory
		mov qword [RENDERER], rax

		;; Print a debug message
		lea rdi, DRENDER
		call printf

		;; The main gawme loop
		.main_loop:

			;; The event loop, which resolves all pending events
			.event_loop:
				lea rdi, EVENT
				call SDL_PollEvent

				cmp rax, 0
				jle .continue

				lea rax, [EVENT + EVTT_OFF]
				cmp dword [rax], EVT_QUIT
				je .exit

				jmp .event_loop

			.continue:
				call collide
				call bapplyvel
				call drawall

		jmp .main_loop

		
		.exit:
		call clean_exit

		ret
