#include "bint.h"

/** assumre that dst->size >= src->size */
void bint_copy(t_bint *dst, t_bint *src) {

	dst->sign = src->sign;
	dst->wordset = src->wordset;
	memcpy(dst->words + dst->size - dst->wordset, src->words + src->size - src->wordset, src->wordset * sizeof(int));
}