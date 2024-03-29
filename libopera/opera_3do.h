#ifndef LIBOPERA_3DO_H_INCLUDED
#define LIBOPERA_3DO_H_INCLUDED

#include "opera_core.h"
#include "opera_vdlp.h"

#include <stdint.h>

EXTERN_C_BEGIN

uint32_t opera_3do_state_size(void);
void     opera_3do_state_save(void *buf);
int      opera_3do_state_load(const void *buf);

int      opera_3do_init(opera_ext_interface_t callback);
void     opera_3do_destroy(void);

void     opera_3do_process_frame(uint32_t *opera_line, uint32_t *opera_field);
//void     opera_3do_process_frame(uint32_t opera_line);
EXTERN_C_END


#endif /* LIBOPERA_3DO_H_INCLUDED */
