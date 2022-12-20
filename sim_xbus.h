
#include "extern_c.h"

#define XBP_INIT	 0	//plugin init, returns plugin version
#define XBP_RESET	 1	//plugin reset with parameter(image path)
#define XBP_SET_COMMAND  2	//XBUS
#define XBP_FIQ		 3	//check interrupt form device
#define XBP_SET_DATA     4	//XBUS
#define XBP_GET_DATA     5	//XBUS
#define XBP_GET_STATUS   6	//XBUS
#define XBP_SET_POLL     7	//XBUS
#define XBP_GET_POLL     8	//XBUS
#define XBP_SELECT	 9      //selects device by Opera
#define XBP_RESERV	 10     //reserved reading from device
#define XBP_DESTROY	 11     //plugin destroy
#define XBP_GET_SAVESIZE 19	//save support from emulator side
#define XBP_GET_SAVEDATA 20
#define XBP_SET_SAVEDATA 21

EXTERN_C_BEGIN

struct xbus_datum_s
{
	uint8_t xb_sel_l;
	uint8_t xb_sel_h;
	uint8_t polf;
	uint8_t poldevf;
	uint8_t stdevf[255]; // status of devices
	uint8_t stlenf; // pointer in FIFO
	uint8_t cmdf[7];
	uint8_t cmdptrf;
};

typedef struct xbus_datum_s xbus_datum_t;

static xbus_datum_t      XBUS;

int sim_xbus_fiq_request;

typedef void* (*sim_xbus_device)(int, void*);

static sim_xbus_device xdev[16];

void     sim_xbus_init(sim_xbus_device zero_dev_);
void     sim_xbus_destroy(void);

int      sim_xbus_attach(sim_xbus_device dev);

void     sim_xbus_device_load(int dev, const char* name);
void     sim_xbus_device_eject(int dev);

void     sim_xbus_set_sel(const uint8_t val_);
uint8_t sim_xbus_get_res(void);

void     sim_xbus_set_poll(const uint8_t val_);
uint8_t sim_xbus_get_poll(void);

void     sim_xbus_fifo_set_cmd(const uint8_t val_);
uint8_t sim_xbus_fifo_get_status(void);

void     sim_xbus_fifo_set_data(const uint8_t val_);
uint8_t sim_xbus_fifo_get_data(void);

uint32_t sim_xbus_state_size(void);
void     sim_xbus_state_save(void* buf_);
void     sim_xbus_state_load(const void* buf_);

EXTERN_C_END
