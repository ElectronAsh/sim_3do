#include "opera_clio.h"
#include "sim_xbus.h"

#include <stdint.h>
#include <string.h>

#define POLSTMASK 0x01
#define POLDTMASK 0x02
#define POLMAMASK 0x04
#define POLREMASK 0x08
#define POLST	  0x10
#define POLDT	  0x20
#define POLMA	  0x40
#define POLRE	  0x80

void
sim_xbus_execute_command_f(void)
{
	if (XBUS.cmdf[0] == 0x83)
	{
		XBUS.stlenf = 12;
		XBUS.stdevf[0] = 0x83;
		XBUS.stdevf[1] = 0x01;
		XBUS.stdevf[2] = 0x01;
		XBUS.stdevf[3] = 0x01;
		XBUS.stdevf[4] = 0x01;
		XBUS.stdevf[5] = 0x01;
		XBUS.stdevf[6] = 0x01;
		XBUS.stdevf[7] = 0x01;
		XBUS.stdevf[8] = 0x01;
		XBUS.stdevf[9] = 0x01;
		XBUS.stdevf[10] = 0x01;
		XBUS.stdevf[11] = 0x01;
		XBUS.poldevf |= POLST;
	}

	if (((XBUS.poldevf & POLST) && (XBUS.poldevf & POLSTMASK)) ||
		((XBUS.poldevf & POLDT) && (XBUS.poldevf & POLDTMASK)))

		//sim_clio_fiq_generate(4, 0);
		sim_xbus_fiq_request = 1;
}

void
sim_xbus_fifo_set_cmd(const uint8_t val_)
{
	if (xdev[XBUS.xb_sel_l])
	{
		xdev[XBUS.xb_sel_l](XBP_SET_COMMAND, (void*)(uintptr_t)val_);
		if (xdev[XBUS.xb_sel_l](XBP_FIQ, NULL))
			//sim_clio_fiq_generate(4, 0);
			sim_xbus_fiq_request = 1;
	}
	else if (XBUS.xb_sel_l == 0x0F)
	{
		if (XBUS.cmdptrf < 7)
		{
			XBUS.cmdf[XBUS.cmdptrf] = val_;
			XBUS.cmdptrf++;
		}

		if (XBUS.cmdptrf >= 7)
		{
			sim_xbus_execute_command_f();
			XBUS.cmdptrf = 0;
		}
	}
}

uint32_t
sim_xbus_fifo_get_data(void)
{
	if (xdev[XBUS.xb_sel_l])
		return (uintptr_t)xdev[XBUS.xb_sel_l](XBP_GET_DATA, NULL);

	return 0;
}

uint32_t
sim_xbus_get_poll(void)
{
	uint32_t res = 0x30;	// Start with 0x30 bits in poll set. DATA and STATUS ready bits???

	if (XBUS.xb_sel_l == 0x0F) res = XBUS.polf;	// If the lower nibble of sel matches 0x0F (device 15, CDROM drive), set result to poll.
	else if (xdev[XBUS.xb_sel_l]) res = (uintptr_t)xdev[XBUS.xb_sel_l](XBP_GET_POLL, NULL);

	if (XBUS.xb_sel_h & 0x80) res &= 0x0F;	// If the MSB bit of sel is set, mask the lower nibble of poll?

	return res;
}

uint32_t
sim_xbus_get_res(void)
{
	if (xdev[XBUS.xb_sel_l])
		return (uintptr_t)xdev[XBUS.xb_sel_l](XBP_RESERV, NULL);
	return 0;
}


uint32_t
sim_xbus_fifo_get_status(void)
{
	uint32_t rv;

	rv = 0;
	if (xdev[XBUS.xb_sel_l])
	{
		rv = (uintptr_t)xdev[XBUS.xb_sel_l](XBP_GET_STATUS, NULL);
	}
	else if (XBUS.xb_sel_l == 0x0F)	// CD drive is selected...
	{
		if (XBUS.stlenf > 0)	// One or more bytes in FIFO buffer.
		{
			rv = XBUS.stdevf[0];	// Read a new byte from the buffer.
			XBUS.stlenf--;			// Decrement the byte count.
			if (XBUS.stlenf > 0)	// Still more bytes left in buffer...
			{
				int i;
				for (i = 0; i < XBUS.stlenf; i++)	// Shift the remaining bytes down, so the latest one is in XBUS.stdevf[0].
					XBUS.stdevf[i] = XBUS.stdevf[i + 1];	// Shuffle the remaining bytes down.
			}
			else
			{
				XBUS.poldevf &= ~POLST;
			}
		}
	}

	return rv;
}

void
sim_xbus_fifo_set_data(const uint8_t val_)
{
	if (xdev[XBUS.xb_sel_l])
		xdev[XBUS.xb_sel_l](XBP_SET_DATA, (void*)(uintptr_t)val_);
}

void
sim_xbus_set_poll(const uint8_t val_)
{
	if (XBUS.xb_sel_l == 0x0F)
	{
		XBUS.polf &= 0xF0;
		XBUS.polf |= (val_ & 0x0F);
	}

	if (xdev[XBUS.xb_sel_l])
	{
		xdev[XBUS.xb_sel_l](XBP_SET_POLL, (void*)(uintptr_t)val_);
		if (xdev[XBUS.xb_sel_l](XBP_FIQ, NULL))
			//sim_clio_fiq_generate(4, 0);
			sim_xbus_fiq_request = 1;
	}
}

void sim_xbus_set_sel(const uint8_t val_)
{
	XBUS.xb_sel_l = (val_ & 0x0F);
	XBUS.xb_sel_h = (val_ & 0xF0);
}

void
sim_xbus_init(sim_xbus_device zero_dev_)
{
	int i;

	XBUS.polf = 0x0F;

	for (i = 0; i < 15; i++)
		xdev[i] = NULL;

	sim_xbus_attach(zero_dev_);
}

int
sim_xbus_attach(sim_xbus_device dev_)
{
	int i;

	for (i = 0; i < 16; i++)	// Find a free device slot.
	{
		if (!xdev[i])
			break;
	}

	if (i == 16)	// Return -1 if no free slots.
		return -1;

	xdev[i] = dev_;				// Else, attach dev to the first available slot.
	xdev[i](XBP_INIT, NULL);	// Init the xbus plugin for this slot / device.

	return i;	// Return the slot number.
}

void
sim_xbus_device_load(int   dev_,
	const char* name_)
{
	xdev[dev_](XBP_RESET, (void*)name_);
}

void sim_xbus_device_eject(int dev_)
{
	xdev[dev_](XBP_RESET, NULL);
}

void
sim_xbus_destroy(void)
{
	unsigned i;

	for (i = 0; i < 16; i++)
	{
		if (xdev[i])
		{
			xdev[i](XBP_DESTROY, NULL);
			xdev[i] = NULL;
		}
	}
}

uint32_t
sim_xbus_state_size(void)
{
	int i;
	uint32_t tmp = sizeof(xbus_datum_t);

	tmp += (16 * 4);
	for (i = 0; i < 15; i++)
	{
		if (!xdev[i])
			continue;
		tmp += (uintptr_t)xdev[i](XBP_GET_SAVESIZE, NULL);
	}

	return tmp;
}

void sim_xbus_state_save(void* buf_)
{
	uint32_t i;
	uint32_t j;
	uint32_t off;
	uint32_t tmp;

	memcpy(buf_, &XBUS, sizeof(xbus_datum_t));

	j = off = sizeof(xbus_datum_t);
	off += (16 * 4);

	for (i = 0; i < 15; i++)
	{
		if (!xdev[i])
		{
			tmp = 0;
			memcpy(&((uint8_t*)buf_)[j + i * 4], &tmp, 4);
		}
		else
		{
			xdev[i](XBP_GET_SAVEDATA, &((uint8_t*)buf_)[off]);
			memcpy(&((uint8_t*)buf_)[j + i * 4], &off, 4);
			off += (uintptr_t)xdev[i](XBP_GET_SAVESIZE, NULL);
		}
	}
}

void
sim_xbus_state_load(const void* buf_)
{
	uint32_t i;
	uint32_t j;
	uint32_t offd;

	j = sizeof(xbus_datum_t);

	memcpy(&XBUS, buf_, j);

	for (i = 0; i < 15; i++)
	{
		memcpy(&offd, &((uint8_t*)buf_)[j + i * 4], 4);

		if (!xdev[i])
			continue;

		if (!offd)
			xdev[i](XBP_RESET, NULL);
		else
			xdev[i](XBP_SET_SAVEDATA, &((uint8_t*)buf_)[offd]);
	}
}
