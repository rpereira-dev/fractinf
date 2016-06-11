#include "bint.h"

/** dump the raw byte of this bcd */
void bcd_dump(t_bcd * bcd) {
	bdump(bcd->raw_bytes, bcd->length);
}

/** delete the bcd */
void bcd_delete(t_bcd **bcd) {
	if (bcd == NULL) {
		return ;
	}
	free((*bcd)->raw_bytes);
	free(*bcd);
	*bcd = NULL;
}

/** a function which shift left the 'len' byte at addr 'addr' */
static void bcd_shift_left_once(unsigned char *addr, size_t len) {
	unsigned char *ptr = addr + len - 1;
	unsigned char *end = addr;
	unsigned char reminder = 0;
	while (ptr >= end) {

		//check overflow (if last bit is set, then it will overflow)
		unsigned char next_reminder = *ptr & (1 << 7);

		//operate the shift
		*ptr = *ptr << 1;

		//if there was a previous overflow, set the first bit
		if (reminder) {
			*ptr = *ptr | 1;
		}
		reminder = next_reminder;
		--ptr;
	}
}

/** interpret the given address has an integer 32 bits array, and swap the endian of each integer */
static void bint_bcd_swap_endian(void *addr, unsigned int nword) {
	unsigned int *words = (unsigned int*)addr;
	int i;

	for (i = 0 ; i < nword ; i++) {
		unsigned int n = words[i];
		words[i] = ((n >> 24) & 0xff) | ((n << 8) & 0xff0000) | ((n >> 8) & 0xff00) | ((n << 24) & 0xff000000);
	}
}

/** implementation based on this document: http://www.tkt.cs.tut.fi/kurssit/1426/S12/Ex/ex4/Binary2BCD.pdf */
t_bcd *bint_to_bcd(t_bint *i) {

	//initialize the bcd
	t_bcd *bcd = (t_bcd*)malloc(sizeof(t_bcd));
	if (bcd == NULL) {
		return (NULL);
	}
	bcd->length = 0;
	bcd->raw_bytes = NULL;

	//if zero, return NULL
	if (i == NULL || bint_is_zero(i)) {
		return (bcd);
	}

	//calculate the integer total size
	size_t wordset = i->words + i->size - i->last_word_set;
	size_t byteset = wordset * sizeof(unsigned int);

	//else calculate the bit sizes
	size_t bitset = byteset * 8;

	//total number of bits for the bcd storage
	size_t nbits_bcd = bitset + 4 * bitset / 3;
	size_t nbytes_bcd = nbits_bcd / 8 + (nbits_bcd % 8 != 0);
	if (nbytes_bcd % sizeof(int) != 0) {
		 nbytes_bcd += (sizeof(int) - nbytes_bcd % sizeof(int));
	}

	//alocate bcd storage
	unsigned char *bcd_str = (unsigned char*)malloc(nbytes_bcd);
	if (bcd_str == NULL) {
		return (bcd);
	}

	//prepare the bcd pointer
	memcpy(bcd_str + nbytes_bcd - byteset, i->last_word_set, byteset);
	memset(bcd_str, 0, nbytes_bcd - byteset);

	//printf("bcd after copy: ", 0), bdump(bcd_str, nbytes_bcd), printf("\n");

	//swap the endian so we always work in little endian
	if (endianness() == BIG_ENDIAN) {
		bint_bcd_swap_endian(bcd_str + nbytes_bcd - byteset, wordset);
	}

	//printf("bcd endian fix: ", 0), bdump(bcd_str, nbytes_bcd), printf("\n");

	//shift so last set bit is right before first column
	unsigned char *bcd_str_begin = bcd_str + nbytes_bcd - byteset;
	//the address of the first bit set
	size_t bits_begin = 0;
	//the address of the last bit set
	size_t bits_end = 0;
	while (!(*bcd_str_begin & (1 << 7))) {

		//do the shift
		bcd_shift_left_once(bcd_str_begin, byteset);
		++bits_end;
	}

	//the address of the last bit set
	bits_end = bitset - bits_end;

	//total number of bits to shift
	size_t nbits = bits_end - bits_begin;

	// bits counter in column
	size_t bits = 0;

	//number of column set
	size_t bytes_in_column = 0;

	//printf("bcd initial   : ", bits), bdump(bcd_str, nbytes_bcd), printf("\n");

	//for each bits
	while (true) {

		//total number of byte hold by the bcd pointer (+ 1 so we handle overflow on shifting)
		size_t bytes_to_shift = byteset + bytes_in_column + 1;
		//where the shift should end
		unsigned char *endshift = bcd_str + nbytes_bcd - bytes_to_shift;
		//do the shift
		bcd_shift_left_once(endshift, bytes_to_shift);

		//printf("bcd shift %4d: ", bits), bdump(bcd_str, nbytes_bcd), printf("\n");

		//increment number of bits in column
		++bits;

		//get the last column content
		unsigned char last_char = *(bcd_str + nbytes_bcd - byteset - bytes_in_column - 1);
		//if non-empty, then we have a new column, increment it
		if (last_char) {
			++bytes_in_column;
		}

		if (bits >= nbits) {
			break ;
		}


		//for each bcd byte column set
		int i;
		for (i = 0; i < bytes_in_column; i++) {
			//get the byte
			unsigned char *byteaddr = bcd_str + nbytes_bcd - byteset - 1 - i;

			//columns (4bits of the byte) can be : 0000 / 0001 / 0010 / 0011 / 1000 / 0101 / 0110 / 0111....
			char col;

			//get the first column
			col = *byteaddr & 0xF;

			//if first column >= 5
			if (col >= 5) {
				unsigned char *add_addr = byteaddr;
				unsigned char to_add = 3;

				while (to_add != 0) {
					unsigned char can_hold = 255 - *add_addr;
					if (can_hold > 3) {
						can_hold = 3;
					}
					to_add -= can_hold;
					*add_addr += can_hold;
					--add_addr;
				}
				//printf("bcd +3(1) %4d: ", bits), bdump(bcd, nbytes_bcd), printf("\n");
			}

			//get the second column
			col = (*byteaddr & 0xF0) >> 4;

			//if the second column >= 5
			if (col >= 5) {
				if (col <= 12) {
					//printf("bcd +3(2) %4d: ", bits), bdump(bcd, nbytes_bcd), printf("\n");
					*byteaddr = (*byteaddr & 0xF) | ((col + 3) << 4);
					//printf("bcd +3(2) %4d: ", bits), bdump(bcd, nbytes_bcd), printf("\n");
				} else {
					//this should never occured, but nevermind, so we make sure no error occured
					puts("WARNING: bcd algorythm error (2nd 4 bytes > 12)");
				}
			}
		}
	}

	//reallocate a memory space to hold the final bcd number
	bcd->length = bytes_in_column;
	bcd->raw_bytes = (unsigned char*)malloc(sizeof(unsigned char) * (bcd->length + 1));

	//copy the data to it
	memcpy(bcd->raw_bytes, bcd_str_begin - bytes_in_column, bytes_in_column);

	//free the big bcd str which we no longer need
	free(bcd_str);

	//last char
	bcd->raw_bytes[bytes_in_column] = 0xFF;

	return (bcd);
}

static char bcd_char_to_decimal(char c) {

	c = c + '0';
	return ((c >= '0' && c <= '9') ? c : '?');
}

/** convert the bcd number to a decimal string */
char *bcd_to_str(t_bcd *bcd) {
	if (bcd == NULL || bcd->length == 0 || bcd->raw_bytes == NULL) {
		return (strdup("0"));
	}

	//skip leading zeroes
	unsigned char *raw_bytes = bcd->raw_bytes;
	unsigned int *ptr = (unsigned int*)raw_bytes;
	while (*ptr == 0) {
		++ptr;
	}
	raw_bytes = (unsigned char*)ptr;
	while (*raw_bytes == 0) {
		++raw_bytes;
	}

	//allocate the new string
	size_t strlength = bcd->length * 2;
	char *str = (char*)malloc(sizeof(char) * (strlength + 1));
	if (str == NULL) {
		return (NULL);
	}

	//handle first two char (so there is no '0' heading the number)
	size_t i = 0;
	size_t j = 0;

	//handle two first chars to avoid a leading zero
	unsigned char c1 = ((raw_bytes[i] & 0xF0) >> 4);
	unsigned char c2 = (raw_bytes[i] & 0xF);
	if (c1 != 0) {
		str[j++] = bcd_char_to_decimal(c1);
	}
	str[j++] = bcd_char_to_decimal(c2);
	++i;

	while (i < bcd->length) {
		
		//get bcd chars
		c1 = ((raw_bytes[i] & 0xF0) >> 4);
		c2 = (raw_bytes[i] & 0xF);

		//add the char
		str[j++] = bcd_char_to_decimal(c1);
		str[j++] = bcd_char_to_decimal(c2);
		++i;
	}
	str[j] = 0;

	return (str);
}