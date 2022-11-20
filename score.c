#include <SDL2/SDL.h>
#include <stdlib.h>
#include <string.h>
#include "font.h"

void render_score(SDL_Renderer *r, unsigned int score, unsigned int w, unsigned int h) {
	char *str = malloc(100);
	sprintf(str, "%d", score);
	for (unsigned i = 0; i < strlen(str); i ++)
		render_char(r, w / 2 + (i * 8) / 2, 100, 5, str[i]);
	free(str);
	return;
}
