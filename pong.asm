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

	;; SDL Event Types
	EVT_QUIT:	equ 0x100
	EVT_KBD1:	equ 0x300
	EVT_KBD2:	equ 0x301

	;; Tells the API to put the window at the center of the screen
	FLAG_CENTER:	equ 0x2FFF0000	

	;; Window dimensions (in pixels)
	WIDTH:		equ 1500
	HEIGHT:		equ 800

	;; Reserve some memory for SDL struct pointers
	;; QWords, 32-bit/e
	WINDOW:		dq 0
	RENDERER:	dq 0

	;; Window title
	TITLE:		db "Pong", 0

	;; Generic SDL error format
	GSDLF:		db "SDL Error: %s", 10, 0

	;; Hex code for double quotes (") in the ASCII table
	QUO:		equ 0x22

	;; Welcome message
	WLCME:		db "Welcome to Piotr K. Wyrwas' ", QUO, "The Mistake" , QUO, 10, 0

	;; Specific SDL errors
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

	;; Keyboard event offsets
	KEVT_KSYM:	equ 16

	;; Keyboard stuff, Pulled from the SDL source code
	SCANCODE_UP:	equ 82
	SCANCODE_DOWN:	equ 81

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

	;; Paddle Width
	PW:	equ 8

	;; Paddle Height
	PH:	equ 100

	;; Paddle Origin (Y-axis)
	YORG:	equ HEIGHT / 2 - PH / 2

	;; Left paddle location (x and y)
	LPX:	dd 0
	LPY:	dd 520

	;; Left paddle velocity
	LPV:	dd 0

	;; Right paddle location (x, y)
	RPX:	dd WIDTH - PW
	RPY:	dd 350

	;; Right paddle velocity
	RPV:	dd 0

	;; Ball size
	BS:	equ 10

	;; Ball origin
	XBORG:	equ WIDTH / 2 - BS / 2
	YBORG:	equ HEIGHT / 2 - BS / 2

	;; Variable ball location
	XB:	dd XBORG
	YB:	dd YBORG

	;; Orginal ball velocities
	VELXORG:	equ 1
	VELYORG:	equ 1

	;; Ball velocities
	VELX:	dd VELXORG
	VELY:	dd VELYORG

	;; Score
	SCORE:	dd 0

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

	;; Exit the program after cleaning up all SDL* objects
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

	;; Check for any collision (window edges + paddles) and alter the velocities accordingly
	;; (ball)
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

		add dword [XB], PW

		inc dword [SCORE]

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

	;; Ball Apply Velocity
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

	;; EDI - Value to clamp, ESI - Min value, EDX - Max value
	;; Ensures the value stays within the given limits
	clamp:
		;; Frame
		push rbp
		mov rbp, rsp

		cmp edi, esi	;; }
		jge .cmp_max	;; } eax = esi (min. value) if edi (input value) is lower than esi (min val.)
		mov eax, esi	;; }

		jmp .end

		.cmp_max:
		cmp edi, edx	;; }
		jle .ncn	;; } eax = edx (max value) if edi (input) is greater than edx (max val.)
		mov eax, edx	;; }

		jmp .end
		
		;; No Correction Needed
		.ncn:
		mov eax, edi

		.end:

		;; End of S. Frame
		mov rsp, rbp
		pop rbp

		ret

	;; Left Paddle velocity
	lpvel:
		;; Stack frame
		push rbp
		mov rbp, rsp

		;; A bit of flow control code here
		mov eax, [LPV]
		cmp eax, 0

		;; Downward acceleration
		jg .accel_dw

		;; Upward acceleration
		jl .accel_uw

		;; No velocity
		jmp .end
		
		.accel_dw:
			mov eax, [LPY]		;; } eax = Left paddle Y - Paddle height
			add eax, PH		;; } = Y coord. at the bottom of the paddle

			cmp eax, HEIGHT		;; } Check collision with the bottom edge
			jge .resv		;; } of the window (screen)

			mov eax, [LPY]		;; }
			inc eax			;; } Apply a downward-facing motion
			mov dword [LPY], eax	;; }
		jmp .end
	
		.accel_uw:
			mov eax, [LPY]		;; } eax = Top of the left paddle

			cmp eax, 0		;; } Check collision with top screen edge
			jle .resv		;; }

			mov eax, [LPY]		;; }
			dec eax			;; } Apply an upward motion
			mov dword [LPY], eax	;; }
		jmp .end

		;; Reset the velocity
		.resv:
			mov dword [LPV], 0

		;; Exit (Fall through from above)
		.end:

		;; End of stack frame
		mov rsp, rbp
		pop rbp

		ret

	;; Automatic Right Paddle
	arpad:
		;; New Stack Frame
		push rbp
		mov rbp, rsp

		mov edi, [YB]		;; We want to clamp the Y coordinate of the ball
		mov esi, 0		;; Between 0 (top of the screen)
		mov edx, HEIGHT		;; }
		sub edx, PH		;; } And (screen height - paddle height)
		call clamp		;; Call the clamp function

		;; Update the Y of the right paddle
		mov dword [RPY], eax

		.end:

		;; Destroy Stack F.
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

		;; Draw the player's score
		mov rdi, [RENDERER]
		mov rsi, [SCORE]
		mov rdx, WIDTH
		mov rcx, HEIGHT
		call render_score

		;; Commit all changes to the screen buffer
		mov rdi, [RENDERER]
		call SDL_RenderPresent

		;; Return to the old frame
		mov rsp, rbp
		pop rbp

		ret

	;; Keyboard Interface
	kbd_iface:
		;; Stack frame
		push rbp
		mov rbp, rsp

		;; Check if we're dealing with a keyboard event
		lea eax, [EVENT + EVTT_OFF]
		cmp dword [eax], EVT_KBD1
		je .kdown

		cmp dword [eax], EVT_KBD2
		je .kup

		jmp .end

		;; If key was pressed ..
		.kdown:

			;; Put the effective address of the keycode (SDL_KeyboardEvent->SDL_Keysym->scancode)
			lea rbx, [EVENT + KEVT_KSYM]

			;; eax = keysym
			mov eax, dword [rbx]
			mov rbx, SCANCODE_UP
			
			;; Check for arrow up
			cmp rax, rbx
			jne .code_down

			;; Put the left paddle in upward motion
			mov dword [LPV], -1

			jmp .end

			;; Check if the key is downward arrow
			.code_down:

			lea rbx, [EVENT + KEVT_KSYM]

			;; eax = keysym
			mov eax, dword [rbx]
			mov rbx, SCANCODE_DOWN

			;; Check if the key is down arrow
			cmp rax, rbx
			jne .end

			;; Make the left paddle move downwards
			mov dword [LPV], 1

		jmp .end

		;; When a key was released, set the left paddle velocity to 0 (make it stop)
		.kup:
			mov dword [LPV], 0

		jmp .end

		.end:

		;; End of stack frame
		mov rsp, rbp
		pop rbp

		ret

	checkwin:
		;; New stack frame
		push rbp
		mov rbp, rsp

		;; Check if the ball is  outside of the display (to the left)
		;; = Player has lost
		mov eax, [XB]
		mov ebx, 0
		cmp eax, ebx
		jg .end

		;; Put the back back at its origin (center of the screen)
		mov dword [XB], XBORG
		mov dword [YB], YBORG
		mov dword [VELX], VELXORG
		mov dword [VELY], VELYORG

		mov dword [SCORE], 0

		.end:

		;; Clear the stack frame
		mov rsp, rbp
		pop rbp

		ret

	;; Delay Short While
	;; btw this is a *very* bad way to do this.
	delshw:
		rdtsc
		;; Stack frame
		push rbp
		mov rbp, rsp

		;; The counter
		mov rax, 0

		.loop:
			inc rax
			cmp rax, 2000000
			jl .loop

		;; Clear the frame
		mov rsp, rbp
		pop rbp

		ret

	main:
		;; Set up the stack frame
		push rbp
		mov rbp, rsp

		lea rdi, WLCME
		call printf

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

				call kbd_iface

				jmp .event_loop

			.continue:
				call collide
				call lpvel
				call bapplyvel
				call arpad
				call checkwin
				call drawall
				call delshw

		jmp .main_loop

		
		.exit:
		call clean_exit

		ret
