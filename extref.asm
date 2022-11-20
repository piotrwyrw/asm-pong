
;; extref.asm
;; Required external C references

;; Simple DirectMedia Layer
[extern SDL_GetError]

[extern SDL_Init]

[extern SDL_CreateWindow]
[extern SDL_DestroyWindow]

[extern SDL_CreateRenderer]
[extern SDL_DestroyRenderer]

[extern SDL_SetRenderDrawColor]
[extern SDL_RenderPresent]
[extern SDL_RenderClear]
[extern SDL_RenderFillRect]

[extern SDL_PollEvent]
[extern SDL_Quit]

;; GNU C Library
[extern printf]
[extern exit]

;; C reference to the score renderer
[extern render_score]
