#define MIN_FRAME 1000
#define MAX_FRAME 2000

#include <iostream>
#include <fstream>
#include <string>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "imgui_functions.h"

#include <verilated.h>

#include "Vcore_3do___024root.h"
#include "Vcore_3do.h"

#include "verilated_vcd_c.h"

// libopera includes...
#include "opera_3do.h"

#include "opera_arm.h"
#include "opera_clio.h"
#include "opera_clock.h"
#include "opera_core.h"
#include "opera_diag_port.h"
#include "opera_dsp.h"
#include "opera_madam.h"
#include "opera_region.h"
#include "opera_sport.h"
#include "opera_vdlp.h"
#include "opera_xbus.h"
#include "opera_xbus_cdrom_plugin.h"
#include "opera_cdrom.h"
#include "opera_nvram.h"

#include "inline.h"

#include "sim_xbus.h"

#include "opera_vdlp_i.h"
//extern vdlp_t   g_VDLP;

uint32_t opera_line;
uint32_t opera_field;


volatile extern xbus_datum_t      XBUS;
volatile extern sim_xbus_device xdev[16];
//extern cdrom_device_t g_CDROM_DEVICE;

volatile extern uint32_t CDIMAGE_SECTOR;

uint8_t* dram;
uint8_t* vram;
int flagtime;
extern arm_core_t CPU;


FILE* logfile;
FILE* inst_file;
FILE* soundfile;
FILE* isofile;
FILE* ramdump;

FILE* cel_file;
uint32_t cel_size = 0;

uint32_t sound_out;


extern int sim_xbus_fiq_request = 0;

#include <d3d11.h>
#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include <tchar.h>


// DirectX data
static ID3D11Device* g_pd3dDevice = NULL;
static ID3D11DeviceContext* g_pd3dDeviceContext = NULL;
static IDXGIFactory* g_pFactory = NULL;
static ID3D11Buffer* g_pVB = NULL;
static ID3D11Buffer* g_pIB = NULL;
static ID3D10Blob* g_pVertexShaderBlob = NULL;
static ID3D11VertexShader* g_pVertexShader = NULL;
static ID3D11InputLayout* g_pInputLayout = NULL;
static ID3D11Buffer* g_pVertexConstantBuffer = NULL;
static ID3D10Blob* g_pPixelShaderBlob = NULL;
static ID3D11PixelShader* g_pPixelShader = NULL;

static ID3D11SamplerState* g_pFontSampler = NULL;
static ID3D11SamplerState* g_pFontSampler2 = NULL;

static ID3D11ShaderResourceView* g_pFontTextureView = NULL;
static ID3D11ShaderResourceView* g_pFontTextureView2 = NULL;

static ID3D11RasterizerState* g_pRasterizerState = NULL;
static ID3D11BlendState* g_pBlendState = NULL;
static ID3D11DepthStencilState* g_pDepthStencilState = NULL;
static int                      g_VertexBufferSize = 5000, g_IndexBufferSize = 10000;


// Instantiation of module.
Vcore_3do* top = new Vcore_3do;

char decode_string[64];
char issue_string[64];
char shifter_string[64];
char alu_string[64];
char memory_string[64];
char rb_string[64];

bool old_fiq_n = 1;

bool next_ack = 0;

bool rom2_select = 0;   // Select the BIOS ROM at startup! (not Kanji).

bool map_bios = 1;
uint32_t rom_byteswapped;
uint32_t rom2_byteswapped;
uint32_t ram_byteswapped;

uint16_t shift_reg = 0;
bool toggle = 1;

char my_string[1024];

bool trace = 0;
bool inst_trace = 0;
bool soundtrace = 0;

int pix_count = 0;

uint32_t cur_pc;
uint32_t old_pc;

bool dump_ram = 0;

unsigned char rgb[3];
bool prev_vsync = 0;
int frame_count = 0;

bool prev_hsync = 0;
int line_count = 0;

bool trig_irq = 0;
bool trig_fiq = 0;

bool run_enable = 0;
bool single_step = 0;
bool multi_step = 0;
int multi_step_amount = 8;

int spr_width = 128;

FILE* vgap;

// Data
static IDXGISwapChain* g_pSwapChain = NULL;
static ID3D11RenderTargetView* g_mainRenderTargetView = NULL;

void CreateRenderTarget()
{
	ID3D11Texture2D* pBackBuffer;
	g_pSwapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (LPVOID*)&pBackBuffer);
	g_pd3dDevice->CreateRenderTargetView(pBackBuffer, NULL, &g_mainRenderTargetView);
	pBackBuffer->Release();
}

void CleanupRenderTarget()
{
	if (g_mainRenderTargetView) { g_mainRenderTargetView->Release(); g_mainRenderTargetView = NULL; }
}

HRESULT CreateDeviceD3D(HWND hWnd)
{
	// Setup swap chain
	DXGI_SWAP_CHAIN_DESC sd;
	ZeroMemory(&sd, sizeof(sd));
	sd.BufferCount = 2;
	sd.BufferDesc.Width = 0;
	sd.BufferDesc.Height = 0;
	sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	sd.BufferDesc.RefreshRate.Numerator = 60;
	sd.BufferDesc.RefreshRate.Denominator = 1;
	sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
	sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	sd.OutputWindow = hWnd;
	sd.SampleDesc.Count = 1;
	sd.SampleDesc.Quality = 0;
	sd.Windowed = TRUE;
	sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

	UINT createDeviceFlags = 0;
	//createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
	D3D_FEATURE_LEVEL featureLevel;
	const D3D_FEATURE_LEVEL featureLevelArray[2] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0, };
	if (D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, createDeviceFlags, featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext) != S_OK)
		return E_FAIL;

	CreateRenderTarget();

	return S_OK;
}

void CleanupDeviceD3D()
{
	CleanupRenderTarget();
	if (g_pSwapChain) { g_pSwapChain->Release(); g_pSwapChain = NULL; }
	if (g_pd3dDeviceContext) { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = NULL; }
	if (g_pd3dDevice) { g_pd3dDevice->Release(); g_pd3dDevice = NULL; }
}

extern LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
		return true;

	switch (msg)
	{
	case WM_SIZE:
		if (g_pd3dDevice != NULL && wParam != SIZE_MINIMIZED)
		{
			CleanupRenderTarget();
			g_pSwapChain->ResizeBuffers(0, (UINT)LOWORD(lParam), (UINT)HIWORD(lParam), DXGI_FORMAT_UNKNOWN, 0);
			CreateRenderTarget();
		}
		return 0;
	case WM_SYSCOMMAND:
		if ((wParam & 0xfff0) == SC_KEYMENU) // Disable ALT application menu
			return 0;
		break;
	case WM_DESTROY:
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hWnd, msg, wParam, lParam);
}

static float values[90] = { 0 };
static int values_offset = 0;

int my_x = 0;
int my_y = 0;

vluint64_t main_time = 0;       // Current simulation time.

unsigned int file_size;
unsigned int iso_size;

unsigned char buffer[16];

unsigned int rom_size = 1024 * 1024;            // 1MB. (8-bit wide, 32-bit access). BIOS.
uint8_t* rom_ptr = (uint8_t*)malloc(rom_size);

unsigned int rom2_size = 1024 * 1024;           // 1MB. (8-bit wide, 32-bit access). Kanji font ROM.
uint8_t* rom2_ptr = (uint8_t*)malloc(rom2_size);

unsigned int ram_size = 1024 * 2048;            // 2MB. (8-bit wide, 32-bit access).
uint8_t* ram_ptr = (uint8_t*)malloc(ram_size);

unsigned int vram_size = 1024 * 1024;			// 1MB. (8-bit wide, 32-bit access).
//unsigned int vram_size = 1024 * 2048;			// 2MB. (8-bit wide, 32-bit access).
uint8_t* vram_ptr = (uint8_t*)malloc(vram_size);

unsigned int nvram_size = 1024 * 128;           // 128KB?
uint8_t* nvram_ptr = (uint8_t*)malloc(nvram_size);

unsigned int disp_size = 1024 * 1024 * 4;       // 4MB. (32-bit wide). Sim display window.
uint32_t* disp_ptr = (uint32_t*)malloc(disp_size);

unsigned int disp2_size = 1024 * 1024 * 4;       // 4MB. (32-bit wide). Opera display window.
uint32_t* disp2_ptr = (uint32_t*)malloc(disp2_size);

double sc_time_stamp() {       // Called by $time in Verilog.
	return main_time;
}

extern opera_cdrom_get_size_cb_t    CDROM_GET_SIZE;
extern opera_cdrom_set_sector_cb_t  CDROM_SET_SECTOR;
extern opera_cdrom_read_sector_cb_t CDROM_READ_SECTOR;

uint16_t CDIMAGE_SECTOR_SIZE = 2048;


static
uint32_t
cdimage_get_size(void)
{
	return (iso_size / CDIMAGE_SECTOR_SIZE);
}

static
void
cdimage_set_sector(const uint32_t sector_)
{
	CDIMAGE_SECTOR = sector_;
}

static
void
cdimage_read_sector(void* buf_)
{	uint32_t start_offset = CDIMAGE_SECTOR * CDIMAGE_SECTOR_SIZE;
	//if (CDIMAGE_SECTOR_SIZE == 2352) start_offset += 16;
	//if ( start_offset>(iso_size -CDIMAGE_SECTOR_SIZE) ) start_offset=(iso_size - CDIMAGE_SECTOR_SIZE);	// Clamp the max offset.
	fseek(isofile, start_offset, SEEK_SET);
	fread(buf_, 1, CDIMAGE_SECTOR_SIZE, isofile);
}


uint32_t g_OPT_VIDEO_WIDTH = 0;
uint32_t g_OPT_VIDEO_HEIGHT = 0;
uint32_t g_OPT_VIDEO_PITCH_SHIFT = 0;
uint32_t g_OPT_VDLP_FLAGS = 0;
uint32_t g_OPT_VDLP_PIXEL_FORMAT = 0;
uint32_t g_OPT_ACTIVE_DEVICES = 0;

void my_opera_init() {
	opera_cdrom_set_callbacks(cdimage_get_size, cdimage_set_sector, cdimage_read_sector);

	//opera_3do_init(libopera_callback);

	opera_clock_init();
	opera_arm_init();

	uint32_t size = (384 * 288 * 4);
	if (!g_VIDEO_BUFFER) g_VIDEO_BUFFER = (uint32_t*)calloc(size, sizeof(uint32_t));
	opera_vdlp_configure(g_VIDEO_BUFFER, (vdlp_pixel_format_e)VDLP_PIXEL_FORMAT_XRGB8888, g_OPT_VDLP_FLAGS);

	dram = opera_arm_ram_get();
	vram = opera_arm_vram_get();

	opera_vdlp_init(vram);
	opera_sport_init(vram);
	opera_madam_init(dram);
	opera_nvram_init();
	
	//opera_xbus_init(xbus_cdrom_plugin);
	//opera_xbus_device_load(0, NULL);
	sim_xbus_init(xbus_cdrom_plugin);
	sim_xbus_device_load(0, NULL);

	cdimage_set_sector(0);

	// 0x40 for start from 3D0-CD
	// 0x01/0x02 from PhotoCD ??
	// (NO use 0x40/0x02 for BIOS test)
	opera_clio_init(0x40);	// bit[6]=DIPIR.
	//opera_clio_init(0x01);		// <- This value gets written to CLIO cstatbits. bit[0]=POR.
	opera_dsp_init();
}


static uint16_t sim_SNDDebugFIFO0;
static uint16_t sim_SNDDebugFIFO1;
static uint16_t sim_RCVDebugFIFO0;
static uint16_t sim_RCVDebugFIFO1;
static uint16_t sim_GetIdx;
static uint16_t sim_SendIdx;

void
sim_diag_port_init(const int32_t test_code_)
{
	int32_t test_code = test_code_;

	sim_GetIdx = 16;
	sim_SendIdx = 16;
	sim_SNDDebugFIFO0 = 0;
	sim_SNDDebugFIFO1 = 0;

	if (test_code >= 0)
	{
		test_code ^= 0xFF;
		test_code |= 0xA000;
	}
	else
	{
		test_code = 0;
	}

	sim_RCVDebugFIFO0 = test_code;
	sim_RCVDebugFIFO1 = test_code;
}


void
sim_diag_port_send(const uint32_t val_)
{
	if (sim_GetIdx != 16)
	{
		sim_GetIdx = 16;
		sim_SendIdx = 16;
		sim_SNDDebugFIFO0 = 0;
		sim_SNDDebugFIFO1 = 0;
	}

	sim_SNDDebugFIFO0 |= ((val_ & 1) << (sim_SendIdx - 1));
	sim_SNDDebugFIFO1 |= (((val_ & 1) >> 1) << (sim_SendIdx - 1));

	sim_SendIdx--;

	if (sim_SendIdx == 0)
		sim_SendIdx = 16;
}

uint32_t
sim_diag_port_get(void)
{
	unsigned int val = 0;

	if (sim_SendIdx != 16)
	{
		sim_GetIdx = 16;
		sim_SendIdx = 16;
	}

	val = ((sim_RCVDebugFIFO0 >> (sim_GetIdx - 1)) & 0x1);
	val |= (((sim_RCVDebugFIFO1 >> (sim_GetIdx - 1)) & 0x1) << 0x1);
	sim_GetIdx--;

	if (sim_GetIdx == 0)
		sim_GetIdx = 16;

	return val;
}


volatile uint32_t vdl_ctl  = 0x00004410;
volatile uint32_t vdl_curr = 0x002C0000;
volatile uint32_t vdl_prev = 0x002C0000;
volatile uint32_t vdl_next = 0x002C0000;

volatile uint32_t clut[256];

void sim_process_vdl() {
	// Load default CLUT...
	clut[0x00] = 0x000000; clut[0x01] = 0x080808; clut[0x02] = 0x101010; clut[0x03] = 0x191919; clut[0x04] = 0x212121; clut[0x05] = 0x292929; clut[0x06] = 0x313131; clut[0x07] = 0x3A3A3A;
	clut[0x08] = 0x424242; clut[0x09] = 0x4A4A4A; clut[0x0A] = 0x525252; clut[0x0B] = 0x5A5A5A; clut[0x0C] = 0x636363; clut[0x0D] = 0x6B6B6B; clut[0x0E] = 0x737373; clut[0x0F] = 0x7B7B7B;
	clut[0x10] = 0x848484; clut[0x11] = 0x8C8C8C; clut[0x12] = 0x949494; clut[0x13] = 0x9C9C9C; clut[0x14] = 0xA5A5A5; clut[0x15] = 0xADADAD; clut[0x16] = 0xB5B5B5; clut[0x17] = 0xBDBDBD;
	clut[0x18] = 0xC5C5C5; clut[0x19] = 0xCECECE; clut[0x1A] = 0xD6D6D6; clut[0x1B] = 0xDEDEDE; clut[0x1C] = 0xE6E6E6; clut[0x1D] = 0xEFEFEF; clut[0x1E] = 0xF8F8F8; clut[0x1F] = 0xFFFFFF;

	uint32_t header = top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma24_curaddr & 0xfffff;	// Mask address to 1MB (VRAM).

	// Read the VDL / CLUT from vram_ptr...
	if (header>0) {
		vdl_ctl = 0x00000000;
		vdl_curr = 0x00000000;
		vdl_prev = 0x00000000;
		vdl_next = 0x00000000;

		for (int i = 0; i <= 35; i++) {
			if (i == 0) {
				vdl_ctl |= (vram_ptr[header + (i*4) + 0]) << 24;
				vdl_ctl |= (vram_ptr[header + (i*4) + 1]) << 16;
				vdl_ctl |= (vram_ptr[header + (i*4) + 2]) << 8;
				vdl_ctl |= (vram_ptr[header + (i*4) + 3]) << 0;
			}
			if (i == 1) {
				vdl_curr |= (vram_ptr[header + (i*4) + 0]) << 24;
				vdl_curr |= (vram_ptr[header + (i*4) + 1]) << 16;
				vdl_curr |= (vram_ptr[header + (i*4) + 2]) << 8;
				vdl_curr |= (vram_ptr[header + (i*4) + 3]) << 0;
			}
			if (i == 2) {
				vdl_prev |= (vram_ptr[header + (i*4) + 0]) << 24;
				vdl_prev |= (vram_ptr[header + (i*4) + 1]) << 16;
				vdl_prev |= (vram_ptr[header + (i*4) + 2]) << 8;
				vdl_prev |= (vram_ptr[header + (i*4) + 3]) << 0;
			}
			if (i == 3) {
				vdl_next |= (vram_ptr[header + (i*4) + 0]) << 24;
				vdl_next |= (vram_ptr[header + (i*4) + 1]) << 16;
				vdl_next |= (vram_ptr[header + (i*4) + 2]) << 8;
				vdl_next |= (vram_ptr[header + (i*4) + 3]) << 0;
			}
			//else if (i>=4) clut[i-4] = vram_ptr[header+i];         // TESTING !!!
		}
	}

	// Copy the VRAM pixels into disp_ptr...
	// Just a dumb test atm. Assuming 16bpp from vram_ptr, with odd and even pixels in the upper/lower 16 bits.
	//
	// vram_ptr is 32-bit wide!
	// vram_size = 1MB, so needs to be divided by 4 if used as an index.
	//
	uint32_t my_line = 0;

	//uint32_t offset = 0xC0000;
	uint32_t offset = vdl_curr & 0xfffff;
	//uint32_t offset = vdl_next & 0xfffff;

	for (uint32_t i = 0; i < (vram_size / 16); i++) {
		uint16_t pixel;

		if ((i % 320) == 0) my_line++;

		pixel = vram_ptr[ (offset+(i*4)+0)&0xfffff ]<<8 | vram_ptr[ (offset+(i*4)+1)&0xfffff ];
		rgb[0] = clut[(pixel & 0x7C00) >> 10] >> 16;
		rgb[1] = clut[(pixel & 0x03E0) >> 5] >> 8;
		rgb[2] = clut[(pixel & 0x001F) << 0] >> 0;
		disp_ptr[i + (my_line * 320)] = 0xff<<24 | rgb[2]<<16 | rgb[1]<<8 | rgb[0];			// Our debugger framebuffer is in the 32-bit ABGR format.

		pixel = vram_ptr[ (offset+(i*4)+2)&0xfffff ]<<8 | vram_ptr[ (offset+(i*4)+3)&0xfffff ];
		rgb[0] = clut[(pixel & 0x7C00) >> 10] >> 16;
		rgb[1] = clut[(pixel & 0x03E0) >> 5] >> 8;
		rgb[2] = clut[(pixel & 0x001F) << 0] >> 0;
		disp_ptr[i + (my_line * 320) + 320] = 0xff<<24 | rgb[2]<<16 | rgb[1]<<8 | rgb[0];	// Our debugger framebuffer is in the 32-bit ABGR format.
	}
}

volatile uint32_t opera_vdl_ctl = 0x00000000;
volatile uint32_t opera_vdl_curr = 0x00000000;
volatile uint32_t opera_vdl_prev = 0x00000000;
volatile uint32_t opera_vdl_next = 0x00000000;

volatile uint32_t opera_clut[256];

void opera_process_vdl() {
	// Load default CLUT...
	clut[0x00] = 0x000000; clut[0x01] = 0x080808; clut[0x02] = 0x101010; clut[0x03] = 0x191919; clut[0x04] = 0x212121; clut[0x05] = 0x292929; clut[0x06] = 0x313131; clut[0x07] = 0x3A3A3A;
	clut[0x08] = 0x424242; clut[0x09] = 0x4A4A4A; clut[0x0A] = 0x525252; clut[0x0B] = 0x5A5A5A; clut[0x0C] = 0x636363; clut[0x0D] = 0x6B6B6B; clut[0x0E] = 0x737373; clut[0x0F] = 0x7B7B7B;
	clut[0x10] = 0x848484; clut[0x11] = 0x8C8C8C; clut[0x12] = 0x949494; clut[0x13] = 0x9C9C9C; clut[0x14] = 0xA5A5A5; clut[0x15] = 0xADADAD; clut[0x16] = 0xB5B5B5; clut[0x17] = 0xBDBDBD;
	clut[0x18] = 0xC5C5C5; clut[0x19] = 0xCECECE; clut[0x1A] = 0xD6D6D6; clut[0x1B] = 0xDEDEDE; clut[0x1C] = 0xE6E6E6; clut[0x1D] = 0xEFEFEF; clut[0x1E] = 0xF8F8F8; clut[0x1F] = 0xFFFFFF;

	volatile uint32_t header = g_VDLP.curr_vdl & 0xfffff;

	// Read the VDL / CLUT from vram_ptr...
	if (header>0) {
		for (int i = 0; i <= 35; i++) {
			if (i == 0) {
				opera_vdl_ctl |= (vram[header + (i*4) + 0]) << 24;
				opera_vdl_ctl |= (vram[header + (i*4) + 1]) << 16;
				opera_vdl_ctl |= (vram[header + (i*4) + 2]) << 8;
				opera_vdl_ctl |= (vram[header + (i*4) + 3]) << 0;
			}
			if (i == 1) {
				opera_vdl_curr |= (vram[header + (i*4) + 0]) << 24;
				opera_vdl_curr |= (vram[header + (i*4) + 1]) << 16;
				opera_vdl_curr |= (vram[header + (i*4) + 2]) << 8;
				opera_vdl_curr |= (vram[header + (i*4) + 3]) << 0;
			}
			if (i == 2) {
				opera_vdl_prev |= (vram[header + (i*4) + 0]) << 24;
				opera_vdl_prev |= (vram[header + (i*4) + 1]) << 16;
				opera_vdl_prev |= (vram[header + (i*4) + 2]) << 8;
				opera_vdl_prev |= (vram[header + (i*4) + 3]) << 0;
			}
			if (i == 3) {
				opera_vdl_next |= (vram[header + (i*4) + 0]) << 24;
				opera_vdl_next |= (vram[header + (i*4) + 1]) << 16;
				opera_vdl_next |= (vram[header + (i*4) + 2]) << 8;
				opera_vdl_next |= (vram[header + (i*4) + 3]) << 0;
			}
			//else if (i>=4) clut[i-4] = vram_ptr[header+i];         // TESTING !!!
		}
	}

	// Copy the VRAM pixels into disp_ptr...
	// Just a dumb test atm. Assuming 16bpp from vram_ptr, with odd and even pixels in the upper/lower 16 bits.
	//
	// vram_ptr is 32-bit wide!
	// vram_size = 1MB, so needs to be divided by 4 if used as an index.
	//

	//uint32_t offset = opera_vdl_curr & 0xfffff;
	//uint32_t offset = opera_vdl_next & 0xfffff;

	uint32_t offset = g_VDLP.curr_bmp & 0xfffff;
	//uint32_t offset = opera_vdlp_bmp_origin & 0xfffff;
	//uint32_t offset = 0x21000;
	//uint32_t offset = 0xC0000;

	uint32_t my_line = opera_line;

	for (int i = 0; i < 320; i++) {
		uint16_t pixel;

		pixel = vram[offset + (i * 4) + 3] << 8 | vram[offset + (i * 4) + 2];
		rgb[0] = clut[(pixel & 0x7C00) >> 10] >> 16;
		rgb[1] = clut[(pixel & 0x03E0) >> 5] >> 8;
		rgb[2] = clut[(pixel & 0x001F) << 0] >> 0;
		disp2_ptr[i + (my_line * 320)] = 0xff << 24 | rgb[2] << 16 | rgb[1] << 8 | rgb[0];			// Our debugger framebuffer is in the 32-bit ABGR format.

		pixel = vram[offset + (i * 4) + 1] << 8 | vram[offset + (i * 4) + 0];
		rgb[0] = clut[(pixel & 0x7C00) >> 10] >> 16;
		rgb[1] = clut[(pixel & 0x03E0) >> 5] >> 8;
		rgb[2] = clut[(pixel & 0x001F) << 0] >> 0;
		disp2_ptr[i + (my_line * 320) + 320] = 0xff << 24 | rgb[2] << 16 | rgb[1] << 8 | rgb[0];	// Our debugger framebuffer is in the 32-bit ABGR format.
	}

	/*
	for (int i = 0; i < (vram_size / 16); i++) {
		uint16_t pixel;

		if ((i % 320) == 0) my_line++;

		pixel = vram[offset + (i * 4) + 3] << 8 | vram[offset + (i * 4) + 2];
		rgb[0] = clut[(pixel & 0x7C00) >> 10] >> 16;
		rgb[1] = clut[(pixel & 0x03E0) >> 5] >> 8;
		rgb[2] = clut[(pixel & 0x001F) << 0] >> 0;
		disp2_ptr[i + (my_line * 320)] = 0xff << 24 | rgb[2] << 16 | rgb[1] << 8 | rgb[0];			// Our debugger framebuffer is in the 32-bit ABGR format.

		pixel = vram[offset + (i * 4) + 1] << 8 | vram[offset + (i * 4) + 0];
		rgb[0] = clut[(pixel & 0x7C00) >> 10] >> 16;
		rgb[1] = clut[(pixel & 0x03E0) >> 5] >> 8;
		rgb[2] = clut[(pixel & 0x001F) << 0] >> 0;
		disp2_ptr[i + (my_line * 320) + 320] = 0xff << 24 | rgb[2] << 16 | rgb[1] << 8 | rgb[0];	// Our debugger framebuffer is in the 32-bit ABGR format.
	}
	*/
}

uint32_t svf_src_addr = 00;
void svf_set_source() {
	svf_src_addr = (top->mem_addr & 0x7ff) << 9;
}

void svf_page_copy() {
	uint32_t dest_addr = (top->mem_addr & 0x7ff) << 9;	// Remember, the *address* is used here, not o_wb_dat.
	uint32_t mask = top->o_wb_dat;                      // The write *data* is used as an mask. I think? ElectronAsh.

	uint32_t keep = mask ^ 0xffffffff;
	uint8_t keep0 = (keep >> 24) & 0xff;
	uint8_t keep1 = (keep >> 16) & 0xff;
	uint8_t keep2 = (keep >> 8) & 0xff;
	uint8_t keep3 = (keep >> 0) & 0xff;
	uint8_t mask0 = (mask >> 24) & 0xff;
	uint8_t mask1 = (mask >> 16) & 0xff;
	uint8_t mask2 = (mask >> 8) & 0xff;
	uint8_t mask3 = (mask >> 0) & 0xff;

	for(int i = 0; i < 2048; i += 4)   // Block size is 2KB. Copying a WORD at a time, so i+=4.
	{
		vram_ptr[dest_addr+i+0] = (vram_ptr[dest_addr+i+0] & keep0) | (vram_ptr[svf_src_addr+i+0] & mask0);
		vram_ptr[dest_addr+i+1] = (vram_ptr[dest_addr+i+1] & keep1) | (vram_ptr[svf_src_addr+i+1] & mask1);
		vram_ptr[dest_addr+i+2] = (vram_ptr[dest_addr+i+2] & keep2) | (vram_ptr[svf_src_addr+i+2] & mask2);
		vram_ptr[dest_addr+i+3] = (vram_ptr[dest_addr+i+3] & keep3) | (vram_ptr[svf_src_addr+i+3] & mask3);
	}
}

uint32_t svf_color = 0;
void svf_set_color() {
	svf_color = top->o_wb_dat;
}

void svf_flash_write() {        // "Color fill", basically.
	uint32_t dest_addr = (top->mem_addr & 0x7ff) << 9;	// Remember, the *address* is used here, not o_wb_dat.
	uint32_t mask = top->o_wb_dat;						// The write *data* is used as an mask. I think? ElectronAsh.

	uint32_t keep = mask ^ 0xffffffff;
	uint8_t keep0 = (keep>>24) & 0xff;
	uint8_t keep1 = (keep>>16) & 0xff;
	uint8_t keep2 = (keep>>8)  & 0xff;
	uint8_t keep3 = (keep>>0)  & 0xff;
	uint8_t mask0 = (mask>>24) & 0xff;
	uint8_t mask1 = (mask>>16) & 0xff;
	uint8_t mask2 = (mask>>8) & 0xff;
	uint8_t mask3 = (mask>>0) & 0xff;

	for (int i = 0; i < 2048; i+=4)   // Block size is 2KB. Writing a WORD at a time, so i+=4.
	{
		vram_ptr[dest_addr+i+0] = (vram_ptr[dest_addr+i+0] & keep0) | ((svf_color>>24) & mask0);
		vram_ptr[dest_addr+i+1] = (vram_ptr[dest_addr+i+1] & keep1) | ((svf_color>>16) & mask1);
		vram_ptr[dest_addr+i+2] = (vram_ptr[dest_addr+i+2] & keep2) | ((svf_color>>8)  & mask2);
		vram_ptr[dest_addr+i+3] = (vram_ptr[dest_addr+i+3] & keep3) | ((svf_color>>0)  & mask3);
	}
}

#define PBUS_BUF_SIZE 256

#define PBUS_FLIGHTSTICK_ID_0       0x01
#define PBUS_FLIGHTSTICK_ID_1       0x7B
#define PBUS_JOYPAD_ID              0x80
#define PBUS_MOUSE_ID               0x49
#define PBUS_LIGHTGUN_ID            0x4D
#define PBUS_ORBATAK_TRACKBALL_ID   PBUS_MOUSE_ID
#define PBUS_ORBATAK_BUTTONS_ID     0xC0

#define PBUS_JOYPAD_SHIFT_LT        0x02
#define PBUS_JOYPAD_SHIFT_RT        0x03
#define PBUS_JOYPAD_SHIFT_X         0x04
#define PBUS_JOYPAD_SHIFT_P         0x05
#define PBUS_JOYPAD_SHIFT_C         0x06
#define PBUS_JOYPAD_SHIFT_B         0x07
#define PBUS_JOYPAD_SHIFT_A         0x00
#define PBUS_JOYPAD_SHIFT_L         0x01
#define PBUS_JOYPAD_SHIFT_R         0x02
#define PBUS_JOYPAD_SHIFT_U         0x03
#define PBUS_JOYPAD_SHIFT_D         0x04

uint8_t pbus_buf[PBUS_BUF_SIZE];
uint32_t pbus_idx;

void pbus_dma() {
	bool jp_d = ImGui::IsKeyPressed(ImGuiKey_DownArrow);
	bool jp_u = ImGui::IsKeyPressed(ImGuiKey_UpArrow);
	bool jp_r = ImGui::IsKeyPressed(ImGuiKey_RightArrow);
	bool jp_l = ImGui::IsKeyPressed(ImGuiKey_LeftArrow);
	bool jp_a = ImGui::IsKeyPressed(ImGuiKey_A);
	bool jp_b = ImGui::IsKeyPressed(ImGuiKey_B);
	bool jp_c = ImGui::IsKeyPressed(ImGuiKey_C);
	bool jp_p = ImGui::IsKeyPressed(ImGuiKey_P);
	bool jp_x = ImGui::IsKeyPressed(ImGuiKey_X);
	bool jp_rt = ImGui::IsKeyPressed(ImGuiKey_R);
	bool jp_lt = ImGui::IsKeyPressed(ImGuiKey_L);

	uint32_t str = top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma23_curaddr;	// 0x570.
	uint32_t len = top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma23_curlen;	// 0x574.
	uint32_t end = top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma23_nextaddr;	// 0x578.

	uint32_t temp_word = 0x00000000;

	str += 4;
	len -= 4;
	end += 4;

	pbus_idx = 0;

	pbus_buf[0] = ((PBUS_JOYPAD_ID) |
		(jp_d << PBUS_JOYPAD_SHIFT_D) |
		(jp_u << PBUS_JOYPAD_SHIFT_U) |
		(jp_r << PBUS_JOYPAD_SHIFT_R) |
		(jp_l << PBUS_JOYPAD_SHIFT_L) |
		(jp_a << PBUS_JOYPAD_SHIFT_A));

	pbus_buf[1] = ((jp_b << PBUS_JOYPAD_SHIFT_B) |
		(jp_c << PBUS_JOYPAD_SHIFT_C) |
		(jp_p << PBUS_JOYPAD_SHIFT_P) |
		(jp_x << PBUS_JOYPAD_SHIFT_X) |
		(jp_rt << PBUS_JOYPAD_SHIFT_RT) |
		(jp_lt << PBUS_JOYPAD_SHIFT_LT));


	temp_word = (pbus_buf[0] << 24) | (pbus_buf[1] << 16) | (pbus_buf[2] << 8) | (pbus_buf[3] << 0);
	//ram_ptr[ dst&0x1fffff ] = temp_word;  // ram_ptr is now BYTE addressed!

	fprintf(logfile, "PBUS DMA  toRAM: 0x%08X  len: 0x%08X  fromRAM: 0x%08X\n", str, len, end);

	/*
	for (int i = 0; i < 8; i+=4) {
			ram_ptr[ (dst&0x1fffff)+i ] = pbus_buf[i+0] << 24;
			temp_word = ram_ptr[ (dst&0x1fffff)+i ];
			ram_ptr[ (dst&0x1fffff)+i ] = temp_word&0xff00ffff | (pbus_buf[i+1] << 16);
			temp_word = ram_ptr[ (dst&0x1fffff)+i ];
			ram_ptr[ (dst&0x1fffff)+i ] = temp_word&0xffff00ff | (pbus_buf[i+2] << 8);
			temp_word = ram_ptr[ (dst&0x1fffff)+i ];
			ram_ptr[ (dst&0x1fffff)+i ] = temp_word&0xffffff00 | (pbus_buf[i+3] << 0);
	}
	*/

	//pbus_buf[pbus_idx++] = 0xffffffff;    // Pad the last word??

	//top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma23_curaddr += len;
	//top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma23_nextaddr += len;

	//0x8000FFFF 0xFFFFFFFF 0xFFFF0000 0xFFFFFFFF
	//0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF 0xFFFFFFFF
	ram_ptr[str+0]= pbus_buf[0]; ram_ptr[str+1]= pbus_buf[1]; ram_ptr[str+2]= 0xff; ram_ptr[str+3]= 0xff,
	ram_ptr[str+4]= 0xff; ram_ptr[str+5]= 0xff; ram_ptr[str+6]= 0xff; ram_ptr[str+7]= 0xff;
	ram_ptr[str+8]= 0xff; ram_ptr[str+9]= 0xff; ram_ptr[str+10]=0xff; ram_ptr[str+11]=0xff,
	ram_ptr[str+12]=0xff; ram_ptr[str+13]=0xff; ram_ptr[str+14]=0xff; ram_ptr[str+15]=0xff;
	ram_ptr[str+16]=0xff; ram_ptr[str+17]=0xff; ram_ptr[str+18]=0x00; ram_ptr[str+19]=0x00,
	ram_ptr[str+20]=0xff; ram_ptr[str+21]=0xff; ram_ptr[str+22]=0xff; ram_ptr[str+23]=0xff;
	ram_ptr[str+24]=0xff; ram_ptr[str+25]=0xff; ram_ptr[str+26]=0xff; ram_ptr[str+27]=0xff,
	ram_ptr[str+28]=0xff; ram_ptr[str+29]=0xff; ram_ptr[str+30]=0xff; ram_ptr[str+31]=0xff;

	ram_ptr[str+32]=0xff; ram_ptr[str+33]=0xff; ram_ptr[str+34]=0xff; ram_ptr[str+35]=0xff;

	top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma23_curlen = 0xfffffffc;	// Set the length to -4 when done?
	top->rootp->core_3do__DOT__clio_inst__DOT__irq1_pend |= 1;              // Bit 0 of irq1_pend is the PBUS DMA Done bit.
	top->rootp->core_3do__DOT__madam_inst__DOT__mctl &= ~0x8000;			// Clear bit 15 (PBUS DMA Enable) of mctl reg.

	/*
	for (int i=str; i<end; i+=4) {
		fprintf(logfile, "0x%08X: ", i);
		fprintf(logfile, "0x%02X%02X%02X%02X\n", ram_ptr[i+0], ram_ptr[i+1], ram_ptr[i+2], ram_ptr[i+3]);
	}
	*/
}


void opera_tick() {
	opera_3do_process_frame(&opera_line, &opera_field);	// Tweaked, to render one LINE at a time. ElectronAsh.

	//opera_arm_execute();		// <- This contains all of our Opera fprintfs.
	//opera_clock_push_cycles(main_time);

	//if (opera_clock_dsp_queued()) libopera_callback(EXT_DSP_TRIGGER, NULL);
	//if (opera_clock_dsp_queued()) opera_lr_dsp_process();

	if (opera_clock_dsp_queued()) {
		//g_DSP_BUF[g_DSP_BUF_IDX++] = opera_dsp_loop();
		//g_DSP_BUF_IDX &= DSP_BUF_SIZE_MASK;
		sound_out = opera_dsp_loop();	// Almost certain this is the DSP sound output. ElectronAsh.
		//fprintf(soundfile, "Sound 0x%08X: ", sound_out);
		if (soundtrace) {
			fputc( (sound_out>>24) & 0xff, soundfile);
			fputc( (sound_out>>16) & 0xff, soundfile);
			fputc( (sound_out>>8)  & 0xff, soundfile);
			fputc( (sound_out>>0)  & 0xff, soundfile);
		}
	}
}

static void sim_clio_handle_dma(uint32_t val_)
{
	if (val_ & 0x00100000)	// Check if the Xbus DMA Enable bit in the write to 0x03400304 (CLIO dmactrl) is set.
	{
		int len;		// Needs to be a signed int, so the while (len >= 0) below works.
		uint32_t trg;
		uint8_t b0, b1, b2, b3;

		trg = top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma20_curaddr;	// 0x03300540. DMA Target (Source/Dest address). Likely always the dest, for a CDROM DMA?
		len = top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma20_curlen;	// 0x03300544. DMA Length (in BYTES).

		fprintf(logfile, "Xbus DMA  trg: 0x%08X  len: 0x%08X\n", trg, len);

		top->rootp->core_3do__DOT__clio_inst__DOT__dmactrl &= ~0x00100000;	// Clear bit [20] in the CLIO dmactrl reg.
		top->rootp->core_3do__DOT__clio_inst__DOT__expctl &= ~0x80;			// Clear bit [7] in the CLIO expctl reg "DMA has control of Xbus".

		//if (top->rootp->core_3do__DOT__clio_inst__DOT__expctl & 0x200)	// XB_DmadirectION bit.There was an "else" after this "if" in
		//{																	// the Opera source, but the code was identical.
			while (len >= 0)												// Very likely because the CDROM drive is always Xbus -> RAM. ElectronAsh.
			{
				b3 = sim_xbus_fifo_get_data();
				b2 = sim_xbus_fifo_get_data();
				b1 = sim_xbus_fifo_get_data();
				b0 = sim_xbus_fifo_get_data();

				//fprintf(logfile, "Addr: 0x%08X  0x%02X%02X%02X%02X\n", trg, b0, b1, b2, b3);

				// Mask address, so DMA can only target 2MB main DRAM ,or 1MB VRAM (but not registers?). ElectronAsh.
				if (trg < 0x200000) {
					ram_ptr[ (trg & 0x1fffff) + 0 ] = b0;
					ram_ptr[ (trg & 0x1fffff) + 1 ] = b1;
					ram_ptr[ (trg & 0x1fffff) + 2 ] = b2;
					ram_ptr[ (trg & 0x1fffff) + 3 ] = b3;
				}
				/*
				else {
					vram_ptr[ (trg & 0xfffff) + 0 ] = b0;
					vram_ptr[ (trg & 0xfffff) + 1 ] = b1;
					vram_ptr[ (trg & 0xfffff) + 2 ] = b2;
					vram_ptr[ (trg & 0xfffff) + 3 ] = b3;
				}
				*/

				trg += 4;
				len -= 4;
			}

			top->rootp->core_3do__DOT__clio_inst__DOT__expctl |= 0x80;	// Set bit [7] in the CLIO expctl reg "ARM has control of Xbus".
		//}

		top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma20_curlen = 0xFFFFFFFC;	// Length reg should end up with this value once it wraps 0?
		top->rootp->core_3do__DOT__clio_inst__DOT__irq0_pend |= (1<<29);		// Set the IRQ0 Pending bit, for "XBus DMA Done"!
	}
}

static
void
sim_if_set_set_reset(uint32_t* output_,
	uint32_t  val_,
	uint32_t  mask_chk_,
	uint32_t  mask_set_)
{
	if ((val_ & mask_chk_) == mask_chk_)
	{
		*output_ = ((val_ & mask_set_) ?
			(*output_ | mask_set_) :
			(*output_ & ~mask_set_));
	}
}

void handle_adbio_write() {
	sim_if_set_set_reset(&top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg, top->o_wb_dat, 0x10, 0x01);
	sim_if_set_set_reset(&top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg, top->o_wb_dat, 0x20, 0x02);
	sim_if_set_set_reset(&top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg, top->o_wb_dat, 0x40, 0x04);
	sim_if_set_set_reset(&top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg, top->o_wb_dat, 0x80, 0x08);
}

int verilate() {
	if (!Verilated::gotFinish()) {
		if (main_time < 50) {
			top->reset_n = 0;		// Assert reset (active LOW)
			frame_count = 0;
		}
		if (main_time == 50) {		// Do == here, so we can still reset it in the main loop.
			top->reset_n = 1;		// Deassert reset./
		}

		if (top->reset_n) {
			/*
			if (top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__o_trace_valid &&
				top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__o_trace_uop_last)
				opera_tick();
			*/

			map_bios = 0;
			top->rootp->core_3do__DOT__madam_inst__DOT__map_bios = 0;
			//top->rootp->core_3do__DOT__madam_inst__DOT__nextccb = 0x000BB770;
			//top->rootp->core_3do__DOT__madam_inst__DOT__nextccb = 0x000B7ee4;
			//top->rootp->core_3do__DOT__madam_inst__DOT__nextccb = 0x000bc4f0;
			//top->rootp->core_3do__DOT__madam_inst__DOT__nextccb = 0x000Bfc70;

			top->rootp->core_3do__DOT__madam_inst__DOT__nextccb = 0x00000000;
		}

		pix_count++;

		uint16_t spr_wi = (top->rootp->core_3do__DOT__madam_inst__DOT__pre1&0x7ff) + 1;
		//uint16_t spr_wi = spr_width;

		/*
		clut[0x00] = 0x35ED42; clut[0x01] = 0x3035EF; clut[0x02] = 0x31CD35; clut[0x03] = 0xAB2DAD; clut[0x04] = 0x3E0E29; clut[0x05] = 0x8B4650; clut[0x06] = 0x256A25; clut[0x07] = 0x492128;
		clut[0x08] = 0x467142; clut[0x09] = 0x514E92; clut[0x0a] = 0x56D44E; clut[0x0b] = 0xB456B2; clut[0x0c] = 0x5EF456; clut[0x0d] = 0xD518E6; clut[0x0e] = 0x1D0614; clut[0x0f] = 0xC56335;
		clut[0x10] = 0x5F176B; clut[0x11] = 0x587399; clut[0x12] = 0x77BA7F; clut[0x13] = 0xFF0C62; clut[0x14] = 0x7BDE00; clut[0x15] = 0x010000; clut[0x16] = 0x000000; clut[0x17] = 0x000000;
		clut[0x18] = 0x000000; clut[0x19] = 0x003FE6; clut[0x1a] = 0x462000; clut[0x1b] = 0x0B8DB0; clut[0x1c] = 0x000B8D; clut[0x1d] = 0xFC000B; clut[0x1e] = 0xB4F400; clut[0x1f] = 0x800000;
		*/

		// PLUT, for coded_packed_6bpp.cel...
		clut[0x00] = 0x7FFF; clut[0x01] = 0x698C; clut[0x02] = 0x64E8; clut[0x03] = 0x60A6; clut[0x04] = 0x7BBD; clut[0x05] = 0x6B5B; clut[0x06] = 0x5EF7; clut[0x07] = 0x4A52;
		clut[0x08] = 0x2951; clut[0x09] = 0x3192; clut[0x0a] = 0x4E73; clut[0x0b] = 0x2110; clut[0x0c] = 0x0C6C; clut[0x0d] = 0x56B5; clut[0x0f] = 0x10AE; clut[0x17] = 0x39CE;
		clut[0x10] = 0x294A; clut[0x11] = 0x1084; clut[0x12] = 0x18C0; clut[0x13] = 0x2528; clut[0x14] = 0x318C; clut[0x15] = 0x2108; clut[0x16] = 0x0840; clut[0x17] = 0x2921;
		clut[0x18] = 0x0000; clut[0x19] = 0x3161; clut[0x1a] = 0x3DC2; clut[0x1b] = 0x4A02; clut[0x1c] = 0x5E83; clut[0x1d] = 0x6AE3; clut[0x1f] = 0x7B64; clut[0x27] = 0x7F84;

		/*
		// PLUT, for one of the BIOS "Please Insert CD" screen CELs...
		clut[0x00] = 0x35ED; clut[0x01] = 0x4230; clut[0x02] = 0x35EF; clut[0x03] = 0x31CD; clut[0x04] = 0x35AB; clut[0x05] = 0x2DAD; clut[0x06] = 0x3E0E; clut[0x07] = 0x298B;
		clut[0x08] = 0x4650; clut[0x09] = 0x256A; clut[0x0a] = 0x2549; clut[0x0b] = 0x2128; clut[0x0c] = 0x4671; clut[0x0d] = 0x4251; clut[0x0e] = 0x4E92; clut[0x0f] = 0x56D4;
		clut[0x10] = 0x4EB4; clut[0x11] = 0x56B2; clut[0x12] = 0x5EF4; clut[0x13] = 0x56D5; clut[0x14] = 0x18E6; clut[0x15] = 0x1D06; clut[0x16] = 0x14C5; clut[0x17] = 0x6335;
		clut[0x18] = 0x5F17; clut[0x19] = 0x6B58; clut[0x1a] = 0x7399; clut[0x1b] = 0x77BA; clut[0x1c] = 0x7FFF; clut[0x1d] = 0x0C62; clut[0x1e] = 0x7BDE; clut[0x1f] = 0x0001;
		clut[0x20] = 0x0000; clut[0x21] = 0x0000; clut[0x22] = 0x0000; clut[0x23] = 0x0000; clut[0x24] = 0x0000; clut[0x25] = 0x0000; clut[0x26] = 0x3FE6; clut[0x27] = 0x4620;
		clut[0x28] = 0x000B; clut[0x29] = 0x8DB0; clut[0x2a] = 0x000B; clut[0x2b] = 0x8DFC; clut[0x2c] = 0x000B; clut[0x2d] = 0xB4F4; clut[0x2e] = 0x0080; clut[0x2f] = 0x0000;
		*/

		//if (top->i_wb_dat==0x00f00104) run_enable = 0;

		/*
		//if (my_x == spr_wi || top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__eol) {
		if (top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__eol) {
			my_x = 0;
			my_y++;
		}
		if (top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__pix_valid) {
			uint16_t colour = clut[top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__col_out];
			rgb[0] = (colour & 0x7C00) >> 7;
			rgb[1] = (colour & 0x03E0) >> 2;
			rgb[2] = (colour & 0x001F) << 3;
			disp_ptr[ ((my_y*320) + my_x) & 0xfffff] = 0xff<<24 | rgb[2]<<16 | rgb[1]<<8 | rgb[0];	// ABGR.
			my_x++;
		}
		*/

		//jp_a = top->rootp->core_3do__DOT__clio_inst__DOT__field;	// Toggling "A" button, to test joypad. (works in BIOS joypad test)

		//cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__pc_from_alu;
		//cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__o_pc_plus_8_ff;
		//cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__postalu_pc_plus_8_ff - 8;
		cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__i_pc_plus_8_buf_ff - 8;

		//if (top->mem_addr==0x000011664) run_enable = 0;

		//if (cur_pc==0x00000ee0) run_enable=0;
		//if (top->mem_addr==0x0000FEDC && top->o_wb_we) run_enable = 0;

		/*
		if (frame_count==30 && top->rootp->core_3do__DOT__clio_inst__DOT__hcnt==0 && top->rootp->core_3do__DOT__clio_inst__DOT__vcnt==9) {
			run_enable = 0;
			//inst_trace = 1;
		}
		*/

		/*
		if (cur_pc == 0x000117F8) {
			inst_trace = 1;
			//run_enable = 0;
		}
		*/

		uint32_t decode_word[16];
		uint32_t issue_word[16];
		uint32_t shifter_word[16];
		uint32_t alu_word[16];
		uint32_t memory_word[16];
		uint32_t rb_word[16];
		for (int i = 0; i < 16; i++) {
			decode_word[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__decode_decompile[i];
			issue_word[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__issue_decompile[i];
			shifter_word[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__shifter_decompile[i];
			alu_word[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__alu_decompile[i];
			memory_word[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__memory_decompile[i];
			rb_word[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__rb_decompile[i];
		}

		for (int i = 0; i < 64; i += 4) {
			decode_string[i + 0] = decode_word[(i >> 2)] >> 0; decode_string[i + 1] = decode_word[(i >> 2)] >> 8; decode_string[i + 2] = decode_word[(i >> 2)] >> 16; decode_string[i + 3] = decode_word[(i >> 2)] >> 24;
			issue_string[i + 0] = issue_word[(i >> 2)] >> 0; issue_string[i + 1] = issue_word[(i >> 2)] >> 8; issue_string[i + 2] = issue_word[(i >> 2)] >> 16; issue_string[i + 3] = issue_word[(i >> 2)] >> 24;
			shifter_string[i + 0] = shifter_word[(i >> 2)] >> 0; shifter_string[i + 1] = shifter_word[(i >> 2)] >> 8; shifter_string[i + 2] = shifter_word[(i >> 2)] >> 16; shifter_string[i + 3] = shifter_word[(i >> 2)] >> 24;
			alu_string[i + 0] = alu_word[(i >> 2)] >> 0; alu_string[i + 1] = alu_word[(i >> 2)] >> 8; alu_string[i + 2] = alu_word[(i >> 2)] >> 16; alu_string[i + 3] = alu_word[(i >> 2)] >> 24;
			memory_string[i + 0] = memory_word[(i >> 2)] >> 0; memory_string[i + 1] = memory_word[(i >> 2)] >> 8; memory_string[i + 2] = memory_word[(i >> 2)] >> 16; memory_string[i + 3] = memory_word[(i >> 2)] >> 24;
			rb_string[i + 0] = rb_word[(i >> 2)] >> 0; rb_string[i + 1] = rb_word[(i >> 2)] >> 8; rb_string[i + 2] = rb_word[(i >> 2)] >> 16; rb_string[i + 3] = rb_word[(i >> 2)] >> 24;
		}

		strrev(decode_string);
		strrev(issue_string);
		strrev(shifter_string);
		strrev(alu_string);
		strrev(memory_string);
		strrev(rb_string);

		/*
		if (inst_trace && decode_string != "IGNORE" && top->o_wb_stb && top->i_wb_ack) {
			//fprintf(inst_file, "PC: 0x%08X   Inst: %s\n", cur_pc, decode_string);
			fprintf(logfile, "PC: 0x%08X   Inst: %s\n", cur_pc, decode_string);
		}
		*/

		/*
		if (top->mem_addr == 0x03400000 && top->o_wb_we) {
			run_enable = 0;
			inst_trace = 1;
		}
		*/

		if (trace) {
			if ( (cur_pc < (old_pc-8)) || (cur_pc > (old_pc+8)) ) {
				uint32_t arm_reg[40];
				for (int i = 0; i < 40; i++) {
					arm_reg[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__mem[i];
				}
				//fprintf(logfile, "PC: 0x%08X  Addr: 0x%08X  dat_i: 0x%08X  dat_o: 0x%08X  write: %d\n", cur_pc, top->mem_addr, top->i_wb_dat, top->o_wb_dat, top->o_wb_we);
				fprintf(logfile, "PC: 0x%08X  Addr: 0x%08X  dat_i: 0x%08X  dat_o: 0x%08X  write: %d\n", cur_pc, top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__postalu_address_ff, top->i_wb_dat, top->o_wb_dat, top->o_wb_we);

				//fprintf(logfile, "          PC: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_issue_main__DOT__o_pc_ff);
				/*
				fprintf(logfile, "          PC: 0x%08X\n", cur_pc);
				fprintf(logfile, "          R0: 0x%08X\n", arm_reg[0]);
				fprintf(logfile, "          R1: 0x%08X\n", arm_reg[1]);
				fprintf(logfile, "          R2: 0x%08X\n", arm_reg[2]);
				fprintf(logfile, "          R3: 0x%08X\n", arm_reg[3]);
				fprintf(logfile, "          R4: 0x%08X\n", arm_reg[4]);
				fprintf(logfile, "          R5: 0x%08X\n", arm_reg[5]);
				fprintf(logfile, "          R6: 0x%08X\n", arm_reg[6]);
				fprintf(logfile, "          R7: 0x%08X\n", arm_reg[7]);
				fprintf(logfile, "          R8: 0x%08X\n", arm_reg[8]);
				fprintf(logfile, "          R9: 0x%08X\n", arm_reg[9]);
				fprintf(logfile, "         R10: 0x%08X\n", arm_reg[10]);
				fprintf(logfile, "         R11: 0x%08X\n", arm_reg[11]);
				fprintf(logfile, "         R12: 0x%08X\n", arm_reg[12]);
				fprintf(logfile, "      SP R13: 0x%08X\n", arm_reg[13]);
				fprintf(logfile, "      LR R14: 0x%08X\n", arm_reg[14]);
				*/
				old_pc = cur_pc;
			}
		}

		//top->i_wb_ack = top->o_wb_stb;

		if ( (top->o_wb_stb && top->i_wb_ack) || top->rootp->core_3do__DOT__madam_inst__DOT__dma_ack) {
			// Handle writes to Main RAM, with byte masking...
			if (top->rootp->core_3do__DOT__madam_inst__DOT__dram_cs && top->mem_wr) {                // 2MB masked.
				//printf("Main RAM Write!  Addr:0x%08X  Data:0x%08X  BE:0x%01X\n", top->mem_addr&0xFFFFF, top->o_wb_dat, top->o_wb_sel);
				if (top->o_wb_sel & 8) ram_ptr[(top->mem_addr & 0x1ffffc) + 0] = (top->o_wb_dat >> 24) & 0xff;  // ram_ptr is now BYTE addressed.
				if (top->o_wb_sel & 4) ram_ptr[(top->mem_addr & 0x1ffffc) + 1] = (top->o_wb_dat >> 16) & 0xff;  // Mask mem_addr to 2MB, ignore the lower two bits, add the offset.
				if (top->o_wb_sel & 2) ram_ptr[(top->mem_addr & 0x1ffffc) + 2] = (top->o_wb_dat >> 8)  & 0xff;
				if (top->o_wb_sel & 1) ram_ptr[(top->mem_addr & 0x1ffffc) + 3] = (top->o_wb_dat >> 0)  & 0xff;
			}

			// Handle writes to VRAM, with byte masking...
			if (top->rootp->core_3do__DOT__madam_inst__DOT__vram_cs && top->mem_wr) {                // 1MB masked.
				//printf("VRAM Write!  Addr:0x%08X  Data:0x%08X  BE:0x%01X\n", top->mem_addr&0xFFFFF, top->o_wb_dat, top->o_wb_sel);
				if (top->o_wb_sel & 8) vram_ptr[(top->mem_addr & 0xffffc) + 0] = (top->o_wb_dat >> 24) & 0xff;  // vram_ptr is now BYTE addressed.
				if (top->o_wb_sel & 4) vram_ptr[(top->mem_addr & 0xffffc) + 1] = (top->o_wb_dat >> 16) & 0xff;  // Mask mem_addr to 1MB, ignore the lower two bits, add the offset.
				if (top->o_wb_sel & 2) vram_ptr[(top->mem_addr & 0xffffc) + 2] = (top->o_wb_dat >> 8)  & 0xff;
				if (top->o_wb_sel & 1) vram_ptr[(top->mem_addr & 0xffffc) + 3] = (top->o_wb_dat >> 0)  & 0xff;
			}

			// Handle writes to NVRAM...
			if (top->mem_addr >= 0x03140000 && top->mem_addr <= 0x0315ffff && top->mem_wr) {          // 128KB Masked.
				nvram_ptr[ (top->mem_addr>>2) & 0x1ffff] = top->o_wb_dat & 0xff;       // Only writes the lower byte from the core to 8-bit NVRAM. mem_addr is the BYTE address, so shouldn't need shifting.
			}

			/*if ((top->mem_addr == 0x03400400) && top->o_wb_we) {	// XBUS direction.
				if (!(top->o_wb_dat & 0x800)) top->rootp->core_3do__DOT__clio_inst__DOT__expctl = top->o_wb_dat;
			}*/
			
			uint8_t rom_byte0 = rom_ptr[(top->mem_addr & 0xffffc) + 0] & 0xff;      // rom_ptr is now BYTE addressed.
			uint8_t rom_byte1 = rom_ptr[(top->mem_addr & 0xffffc) + 1] & 0xff;      // Mask mem_addr to 1MB, ignorring the lower two bits, add the offset.
			uint8_t rom_byte2 = rom_ptr[(top->mem_addr & 0xffffc) + 2] & 0xff;
			uint8_t rom_byte3 = rom_ptr[(top->mem_addr & 0xffffc) + 3] & 0xff;
			uint32_t rom_word = rom_byte0 << 24 | rom_byte1 << 16 | rom_byte2 << 8 | rom_byte3;

			uint8_t rom2_byte0 = rom2_ptr[(top->mem_addr & 0xffffc) + 0] & 0xff;    // rom2_ptr is now BYTE addressed.
			uint8_t rom2_byte1 = rom2_ptr[(top->mem_addr & 0xffffc) + 1] & 0xff;    // Mask mem_addr to 1MB, ignorring the lower two bits, add the offset.
			uint8_t rom2_byte2 = rom2_ptr[(top->mem_addr & 0xffffc) + 2] & 0xff;
			uint8_t rom2_byte3 = rom2_ptr[(top->mem_addr & 0xffffc) + 3] & 0xff;
			uint32_t rom2_word = rom2_byte0 << 24 | rom2_byte1 << 16 | rom2_byte2 << 8 | rom2_byte3;
			//uint32_t rom2_word = 0x00000000;	// TESTING. Disable the Kanji ROM for now. Text on BIOS should then be in English.

			uint8_t ram_byte0 = ram_ptr[(top->mem_addr & 0x1ffffc) + 0] & 0xff;     // ram_ptr is now BYTE addressed.
			uint8_t ram_byte1 = ram_ptr[(top->mem_addr & 0x1ffffc) + 1] & 0xff;     // Mask mem_addr to 2MB, ignorring the lower two bits, add the offset.
			uint8_t ram_byte2 = ram_ptr[(top->mem_addr & 0x1ffffc) + 2] & 0xff;
			uint8_t ram_byte3 = ram_ptr[(top->mem_addr & 0x1ffffc) + 3] & 0xff;
			uint32_t ram_word = ram_byte0 << 24 | ram_byte1 << 16 | ram_byte2 << 8 | ram_byte3;

			uint8_t vram_byte0 = vram_ptr[(top->mem_addr & 0xffffc) + 0] & 0xff;     // vram_ptr is now BYTE addressed.
			uint8_t vram_byte1 = vram_ptr[(top->mem_addr & 0xffffc) + 1] & 0xff;     // Mask mem_addr to 1MB, ignorring the lower two bits, add the offset.
			uint8_t vram_byte2 = vram_ptr[(top->mem_addr & 0xffffc) + 2] & 0xff;
			uint8_t vram_byte3 = vram_ptr[(top->mem_addr & 0xffffc) + 3] & 0xff;
			uint32_t vram_word = vram_byte0 << 24 | vram_byte1 << 16 | vram_byte2 << 8 | vram_byte3;

			//if (top->mem_addr >= 0x03100000 && top->mem_addr <= 0x034FFFFF && top->mem_addr != 0x03400034) fprintf(logfile, "Addr: 0x%08X ", top->mem_addr);
			if (top->mem_addr >= 0x03100000 && top->mem_addr <= 0x034FFFFF && top->mem_addr != 0x03400034) fprintf(logfile, "Addr: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__postalu_address_ff);
			
			// Handle Xbus writes...
			if ((top->mem_addr >= 0x03400500) && (top->mem_addr <= 0x0340053f) && top->o_wb_we) { fprintf(logfile, "CLIO sel        "); sim_xbus_set_sel(top->o_wb_dat & 0xff); }
			else if ((top->mem_addr >= 0x03400540) && (top->mem_addr <= 0x0340057f) && top->o_wb_we) { fprintf(logfile, "CLIO poll       "); sim_xbus_set_poll(top->o_wb_dat & 0xff); }
			else if ((top->mem_addr >= 0x03400580) && (top->mem_addr <= 0x034005bf) && top->o_wb_we) { fprintf(logfile, "CLIO CmdStFIFO  "); sim_xbus_fifo_set_cmd(top->o_wb_dat & 0xff); }		// on FIFO Filled execute the command.
			else if ((top->mem_addr >= 0x034005C0) && (top->mem_addr <= 0x034005ff) && top->o_wb_we) { fprintf(logfile, "CLIO Data FIFO  "); sim_xbus_fifo_set_data(top->o_wb_dat & 0xff); }	// on FIFO Filled execute the command.

			// Tech manual suggests "Any write to this area will unmap the BIOS".
			if (top->rootp->core_3do__DOT__madam_inst__DOT__dram_cs && top->o_wb_we) map_bios = 0;

			// Main RAM reads...
			//if (top->mem_addr >= 0x00000000 && top->mem_addr <= 0x001FFFFF) {
			//if (top->rootp->core_3do__DOT__madam_inst__DOT__dram_cs) {
				if (map_bios) top->i_wb_dat = rom_word;
				else top->i_wb_dat = ram_word;
			//}

			if (top->mem_addr >= 0x00200000 && top->mem_addr <= 0x003FFFFF) { /*fprintf(logfile, "VRAM            ");*/ top->i_wb_dat = vram_word; }

			// BIOS reads...
			//else if (top->mem_addr >= 0x03000510 && top->mem_addr <= 0x03000510) top->i_wb_dat = 0xE1A00000;  // NOP ! (MOV R0,R0) Skip another delay.
			//else if (top->mem_addr >= 0x03000504 && top->mem_addr <= 0x0300050C) top->i_wb_dat = 0xE1A00000;  // NOP ! (MOV R0,R0) Skip another delay.
			//else if (top->mem_addr >= 0x03000340 && top->mem_addr <= 0x03000340) top->i_wb_dat = 0xE1A00000;  // NOP ! (MOV R0,R0) Skip endless loop on mem size check fail.
			//else if (top->mem_addr >= 0x030006a8 && top->mem_addr <= 0x030006b0) top->i_wb_dat = 0xE1A00000;  // NOP ! (MOV R0,R0) Skip test_vram_svf.
			else if (top->mem_addr >= 0x03000000 && top->mem_addr <= 0x030FFFFF) { /*fprintf(logfile, "BIOS            ");*/
				if (rom2_select == 0) top->i_wb_dat = rom_word; else { top->i_wb_dat = rom2_word; }
			}

			//else if (top->mem_addr >= 0x03100000 && top->mem_addr <= 0x0313FFFF) { fprintf(logfile, "Brooktree       "); top->i_wb_dat = 0xBADACCE5; }
			else if (top->mem_addr >= 0x03100000 && top->mem_addr <= 0x0313FFFF) { fprintf(logfile, "Brooktree       "); top->i_wb_dat = 0x0000006A; }

			else if (top->mem_addr >= 0x03140000 && top->mem_addr <= 0x0315FFFF) { fprintf(logfile, "NVRAM           "); top->i_wb_dat = nvram_ptr[ (top->mem_addr>>2) & 0x1ffff] & 0xff; }
			else if (top->mem_addr == 0x03180000 && top->o_wb_we) { fprintf(logfile, "DiagPort        "); sim_diag_port_send(top->o_wb_dat); }
			else if (top->mem_addr == 0x03180000 && !top->o_wb_we) { fprintf(logfile, "DiagPort        "); top->i_wb_dat = sim_diag_port_get(); }
			else if (top->mem_addr >= 0x03180004 && top->mem_addr <= 0x031BFFFF) { fprintf(logfile, "Slow Bus        "); top->i_wb_dat = 0x00000000; }

			else if (top->mem_addr >= 0x03200000 && top->mem_addr <= 0x03200fff && !top->o_wb_we) { fprintf(logfile, "VRAM SVF Source "); svf_set_source(); top->i_wb_dat = 0x00000000; }
			else if (top->mem_addr >= 0x03200000 && top->mem_addr <= 0x03200fff && top->o_wb_we) { fprintf(logfile, "VRAM SVF Copy   "); svf_page_copy(); }
			else if (top->mem_addr >= 0x03202000 && top->mem_addr <= 0x03202fff && top->o_wb_we) { fprintf(logfile, "VRAM SVF Color  "); svf_set_color(); }
			else if (top->mem_addr >= 0x03204000 && top->mem_addr <= 0x03204fff && top->o_wb_we) { fprintf(logfile, "VRAM SVF Flash  ");  svf_flash_write(); }
			else if (top->mem_addr >= 0x03206000 && top->mem_addr <= 0x03206fff) { fprintf(logfile, "VRAM SVF Refresh"); top->i_wb_dat = 0xBADACCE5; }

			else if (top->mem_addr >= 0x032F0000 && top->mem_addr <= 0x032FFFFF) { fprintf(logfile, "Unknown         "); top->i_wb_dat = 0xBADACCE5; }


			// Every core access from here down, gets its data from the Verilog MADAM / CLIO...
			// 
			// MADAM...
			if (top->mem_addr == 0x03300000 && !top->o_wb_we) { fprintf(logfile, "MADAM Revision  "); }
			if (top->mem_addr == 0x03300000 && top->o_wb_we) { fprintf(logfile, "MADAM Print     "); MyAddLog("%c", top->o_wb_dat & 0xff); printf("%c", top->o_wb_dat & 0xff); }
			
			if (top->mem_addr == 0x03300004) { fprintf(logfile, "MADAM msysbits  "); }
			if (top->mem_addr == 0x03300008) { fprintf(logfile, "MADAM mctl      "); }
			if (top->mem_addr == 0x0330000C) { fprintf(logfile, "MADAM sltime    "); }
			if (top->mem_addr >= 0x03300010 && top->mem_addr <= 0x0330001f) { fprintf(logfile, "MADAM MultiChip "); }

			if (top->mem_addr == 0x03300020) { fprintf(logfile, "MADAM Abortbits "); }
			if (top->mem_addr == 0x03300024) { fprintf(logfile, "MADAM Privbits  "); }
			if (top->mem_addr == 0x03300028) { fprintf(logfile, "MADAM StatBits  "); }
			if (top->mem_addr == 0x0330002c) { fprintf(logfile, "MADAM Rsrvd 2c  "); }

			if (top->mem_addr == 0x03300030) { fprintf(logfile, "MADAM Rsrvd 30  "); }
			if (top->mem_addr == 0x03300040) { fprintf(logfile, "MADAM Diag/hcnt "); }
			if (top->mem_addr == 0x03300044) { fprintf(logfile, "MADAM Spare 44  "); }
			if (top->mem_addr == 0x03300048) { fprintf(logfile, "MADAM Rsrvd 48  "); }
			if (top->mem_addr == 0x03300080) { fprintf(logfile, "MADAM Rsrvd 80  "); }

			if (top->mem_addr == 0x03300100) { fprintf(logfile, "MADAM CELStart  "); }
			if (top->mem_addr == 0x03300104) { fprintf(logfile, "MADAM CELStop   "); }
			if (top->mem_addr == 0x03300108) { fprintf(logfile, "MADAM CELCont   "); }
			if (top->mem_addr == 0x0330010c) { fprintf(logfile, "MADAM CELPause  "); }
			if (top->mem_addr == 0x03300110) { fprintf(logfile, "MADAM CCBCtl0   "); }
			if (top->mem_addr == 0x03300114) { fprintf(logfile, "MADAM Rsrvd 114 "); }
			if (top->mem_addr == 0x03300120) { fprintf(logfile, "MADAM CCB_PIXC  "); }

			if (top->mem_addr == 0x03300130) { fprintf(logfile, "MADAM RegisCtl0 "); }
			if (top->mem_addr == 0x03300134) { fprintf(logfile, "MADAM RegisCtl1 "); }
			if (top->mem_addr == 0x03300138) { fprintf(logfile, "MADAM RegisCtl2 "); }
			if (top->mem_addr == 0x0330013c) { fprintf(logfile, "MADAM RegisCtl3 "); }

			if (top->mem_addr == 0x03300140) { fprintf(logfile, "MADAM XYPosH    "); }
			if (top->mem_addr == 0x03300144) { fprintf(logfile, "MADAM XYPosL    "); }
			if (top->mem_addr == 0x03300148) { fprintf(logfile, "MADAM Line_dXYH "); }
			if (top->mem_addr == 0x0330014c) { fprintf(logfile, "MADAM Line_dXYL "); }
			if (top->mem_addr == 0x03300150) { fprintf(logfile, "MADAM dXYH      "); }
			if (top->mem_addr == 0x03300154) { fprintf(logfile, "MADAM dXYL      "); }
			if (top->mem_addr == 0x03300158) { fprintf(logfile, "MADAM ddXYH     "); }
			if (top->mem_addr == 0x0330015c) { fprintf(logfile, "MADAM ddXYL     "); }
			if (top->mem_addr == 0x03300160) { fprintf(logfile, "MADAM Rsrvd 160 "); }

			if (top->mem_addr >= 0x03300180 && top->mem_addr <= 0x033001ff) { fprintf(logfile, "MADAM PLUT      "); }

			if (top->mem_addr == 0x03300218) { fprintf(logfile, "MADAM Fence0    "); }
			if (top->mem_addr == 0x0330021c) { fprintf(logfile, "MADAM Fence1    "); }
			if (top->mem_addr == 0x03300238) { fprintf(logfile, "MADAM Fence2    "); }
			if (top->mem_addr == 0x0330023c) { fprintf(logfile, "MADAM Fence3    "); }

			if (top->mem_addr == 0x03300400) { fprintf(logfile, "MADAM DMA00 Adr "); } // RamToDSPP0
			if (top->mem_addr == 0x03300404) { fprintf(logfile, "MADAM DMA00 Len "); }
			if (top->mem_addr == 0x03300408) { fprintf(logfile, "MADAM DMA00 NAd "); }
			if (top->mem_addr == 0x0330040c) { fprintf(logfile, "MADAM DMA00 NLn "); }

			if (top->mem_addr == 0x03300410) { fprintf(logfile, "MADAM DMA01 Adr "); } // RamToDSPP1
			if (top->mem_addr == 0x03300414) { fprintf(logfile, "MADAM DMA01 Len "); }
			if (top->mem_addr == 0x03300418) { fprintf(logfile, "MADAM DMA01 NAd "); }
			if (top->mem_addr == 0x0330041c) { fprintf(logfile, "MADAM DMA01 NLn "); }

			if (top->mem_addr == 0x03300420) { fprintf(logfile, "MADAM DMA02 Adr "); } // RamToDSPP2
			if (top->mem_addr == 0x03300424) { fprintf(logfile, "MADAM DMA02 Len "); }
			if (top->mem_addr == 0x03300428) { fprintf(logfile, "MADAM DMA02 NAd "); }
			if (top->mem_addr == 0x0330042c) { fprintf(logfile, "MADAM DMA02 NLn "); }

			if (top->mem_addr == 0x03300430) { fprintf(logfile, "MADAM DMA03 Adr "); } // RamToDSPP3
			if (top->mem_addr == 0x03300434) { fprintf(logfile, "MADAM DMA03 Len "); }
			if (top->mem_addr == 0x03300438) { fprintf(logfile, "MADAM DMA03 NAd "); }
			if (top->mem_addr == 0x0330043c) { fprintf(logfile, "MADAM DMA03 NLn "); }

			if (top->mem_addr == 0x03300440) { fprintf(logfile, "MADAM DMA04 Adr "); } // RamToDSPP4
			if (top->mem_addr == 0x03300444) { fprintf(logfile, "MADAM DMA04 Len "); }
			if (top->mem_addr == 0x03300448) { fprintf(logfile, "MADAM DMA04 NAd "); }
			if (top->mem_addr == 0x0330044c) { fprintf(logfile, "MADAM DMA04 NLn "); }

			if (top->mem_addr == 0x03300450) { fprintf(logfile, "MADAM DMA05 Adr "); } // RamToDSPP5
			if (top->mem_addr == 0x03300454) { fprintf(logfile, "MADAM DMA05 Len "); }
			if (top->mem_addr == 0x03300458) { fprintf(logfile, "MADAM DMA05 NAd "); }
			if (top->mem_addr == 0x0330045c) { fprintf(logfile, "MADAM DMA05 NLn "); }

			if (top->mem_addr == 0x03300460) { fprintf(logfile, "MADAM DMA06 Adr "); } // RamToDSPP6
			if (top->mem_addr == 0x03300464) { fprintf(logfile, "MADAM DMA06 Len "); }
			if (top->mem_addr == 0x03300468) { fprintf(logfile, "MADAM DMA06 NAd "); }
			if (top->mem_addr == 0x0330046c) { fprintf(logfile, "MADAM DMA06 NLn "); }

			if (top->mem_addr == 0x03300470) { fprintf(logfile, "MADAM DMA07 Adr "); } // RamToDSPP7
			if (top->mem_addr == 0x03300474) { fprintf(logfile, "MADAM DMA07 Len "); }
			if (top->mem_addr == 0x03300478) { fprintf(logfile, "MADAM DMA07 NAd "); }
			if (top->mem_addr == 0x0330047c) { fprintf(logfile, "MADAM DMA07 NLn "); }

			if (top->mem_addr == 0x03300480) { fprintf(logfile, "MADAM DMA08 Adr "); } // RamToDSPP8
			if (top->mem_addr == 0x03300484) { fprintf(logfile, "MADAM DMA08 Len "); }
			if (top->mem_addr == 0x03300488) { fprintf(logfile, "MADAM DMA08 NAd "); }
			if (top->mem_addr == 0x0330048c) { fprintf(logfile, "MADAM DMA08 NLn "); }

			if (top->mem_addr == 0x03300490) { fprintf(logfile, "MADAM DMA09 Adr "); } // RamToDSPP9
			if (top->mem_addr == 0x03300494) { fprintf(logfile, "MADAM DMA09 Len "); }
			if (top->mem_addr == 0x03300498) { fprintf(logfile, "MADAM DMA09 NAd "); }
			if (top->mem_addr == 0x0330049c) { fprintf(logfile, "MADAM DMA09 NLn "); }

			if (top->mem_addr == 0x033004a0) { fprintf(logfile, "MADAM DMA10 Adr "); } // RamToDSPP10
			if (top->mem_addr == 0x033004a4) { fprintf(logfile, "MADAM DMA10 Len "); }
			if (top->mem_addr == 0x033004a8) { fprintf(logfile, "MADAM DMA10 NAd "); }
			if (top->mem_addr == 0x033004ac) { fprintf(logfile, "MADAM DMA10 NLn "); }

			if (top->mem_addr == 0x033004b0) { fprintf(logfile, "MADAM DMA11 Adr "); } // RamToDSPP11
			if (top->mem_addr == 0x033004b4) { fprintf(logfile, "MADAM DMA11 Len "); }
			if (top->mem_addr == 0x033004b8) { fprintf(logfile, "MADAM DMA11 NAd "); }
			if (top->mem_addr == 0x033004bc) { fprintf(logfile, "MADAM DMA11 NLn "); }

			if (top->mem_addr == 0x033004c0) { fprintf(logfile, "MADAM DMA12 Adr "); } // RamToDSPP12
			if (top->mem_addr == 0x033004c4) { fprintf(logfile, "MADAM DMA12 Len "); }
			if (top->mem_addr == 0x033004c8) { fprintf(logfile, "MADAM DMA12 NAd "); }
			if (top->mem_addr == 0x033004cc) { fprintf(logfile, "MADAM DMA12 NLn "); }

			if (top->mem_addr == 0x033004d0) { fprintf(logfile, "MADAM DMA13 Adr "); } // RamToUncle
			if (top->mem_addr == 0x033004d4) { fprintf(logfile, "MADAM DMA13 Len "); }
			if (top->mem_addr == 0x033004d8) { fprintf(logfile, "MADAM DMA13 NAd "); }
			if (top->mem_addr == 0x033004dc) { fprintf(logfile, "MADAM DMA13 NLn "); }

			if (top->mem_addr == 0x033004e0) { fprintf(logfile, "MADAM DMA14 Adr "); } // RamToExternal
			if (top->mem_addr == 0x033004e4) { fprintf(logfile, "MADAM DMA14 Len "); }
			if (top->mem_addr == 0x033004e8) { fprintf(logfile, "MADAM DMA14 NAd "); }
			if (top->mem_addr == 0x033004ec) { fprintf(logfile, "MADAM DMA14 NLn "); }

			if (top->mem_addr == 0x033004f0) { fprintf(logfile, "MADAM DMA15 Adr "); } // RamToDSPPNStack
			if (top->mem_addr == 0x033004f4) { fprintf(logfile, "MADAM DMA15 Len "); }
			if (top->mem_addr == 0x033004f8) { fprintf(logfile, "MADAM DMA15 NAd "); }
			if (top->mem_addr == 0x033004fc) { fprintf(logfile, "MADAM DMA15 NLn "); }

			if (top->mem_addr == 0x03300500) { fprintf(logfile, "MADAM DMA16 Adr "); } // DSPPToRam0
			if (top->mem_addr == 0x03300504) { fprintf(logfile, "MADAM DMA16 Len "); }
			if (top->mem_addr == 0x03300508) { fprintf(logfile, "MADAM DMA16 NAd "); }
			if (top->mem_addr == 0x0330050c) { fprintf(logfile, "MADAM DMA16 NLn "); }

			if (top->mem_addr == 0x03300510) { fprintf(logfile, "MADAM DMA10 Adr "); } // DSPPToRam1
			if (top->mem_addr == 0x03300514) { fprintf(logfile, "MADAM DMA10 Len "); }
			if (top->mem_addr == 0x03300518) { fprintf(logfile, "MADAM DMA10 NAd "); }
			if (top->mem_addr == 0x0330051c) { fprintf(logfile, "MADAM DMA10 NLn "); }

			if (top->mem_addr == 0x03300520) { fprintf(logfile, "MADAM DMA11 Adr "); } // DSPPToRam2
			if (top->mem_addr == 0x03300524) { fprintf(logfile, "MADAM DMA11 Len "); }
			if (top->mem_addr == 0x03300528) { fprintf(logfile, "MADAM DMA11 NAd "); }
			if (top->mem_addr == 0x0330052c) { fprintf(logfile, "MADAM DMA11 NLn "); }

			if (top->mem_addr == 0x03300530) { fprintf(logfile, "MADAM DMA12 Adr "); } // DSPPToRam3
			if (top->mem_addr == 0x03300534) { fprintf(logfile, "MADAM DMA12 Len "); }
			if (top->mem_addr == 0x03300538) { fprintf(logfile, "MADAM DMA12 NAd "); }
			if (top->mem_addr == 0x0330053c) { fprintf(logfile, "MADAM DMA12 NLn "); }

			if (top->mem_addr == 0x03300540) { fprintf(logfile, "MADAM XBus Adr  "); } // DMAExpo
			if (top->mem_addr == 0x03300544) { fprintf(logfile, "MADAM XBus Len  "); }
			if (top->mem_addr == 0x03300548) { fprintf(logfile, "MADAM XBus NAd  "); }
			if (top->mem_addr == 0x0330054c) { fprintf(logfile, "MADAM XBus NLn  "); }

			if (top->mem_addr == 0x03300550) { fprintf(logfile, "MADAM DMA14 Adr "); } // UncleToRam
			if (top->mem_addr == 0x03300554) { fprintf(logfile, "MADAM DMA14 Len "); }
			if (top->mem_addr == 0x03300558) { fprintf(logfile, "MADAM DMA14 NAd "); }
			if (top->mem_addr == 0x0330055c) { fprintf(logfile, "MADAM DMA14 NLn "); }

			if (top->mem_addr == 0x03300560) { fprintf(logfile, "MADAM DMA15 Adr "); } // ExternalToRam
			if (top->mem_addr == 0x03300564) { fprintf(logfile, "MADAM DMA15 Len "); }
			if (top->mem_addr == 0x03300568) { fprintf(logfile, "MADAM DMA15 NAd "); }
			if (top->mem_addr == 0x0330056c) { fprintf(logfile, "MADAM DMA15 NLn "); }

			if (top->mem_addr == 0x03300570) { fprintf(logfile, "MADAM PbToRam   "); } // ControlPort (PlayerBus)
			if (top->mem_addr == 0x03300574) { fprintf(logfile, "MADAM PbLength  "); }
			if (top->mem_addr == 0x03300578) { fprintf(logfile, "MADAM PbFromRam "); }
			if (top->mem_addr == 0x0330057c) { fprintf(logfile, "MADAM PbRefresh "); }

			//if (top->mem_addr == 0x03300580) { fprintf(logfile, "MADAM CLUT Ctrl "); } // CLUT_MID (CLUT Ctrl)
			if (top->mem_addr == 0x03300580) { fprintf(logfile, "MADAM vdl_addr! "); }
			if (top->mem_addr == 0x03300584) { fprintf(logfile, "MADAM CLUT Vid  "); }
			if (top->mem_addr == 0x03300588) { fprintf(logfile, "MADAM CLUT Mid  "); }
			if (top->mem_addr == 0x0330058c) { fprintf(logfile, "MADAM CMID Rsvd "); }

			if (top->mem_addr == 0x03300590) { fprintf(logfile, "MADAM VID Prev  "); } // Video_MID
			if (top->mem_addr == 0x03300594) { fprintf(logfile, "MADAM VID Curr  "); }
			if (top->mem_addr == 0x03300598) { fprintf(logfile, "MADAM VID PrevM "); }
			if (top->mem_addr == 0x0330059c) { fprintf(logfile, "MADAM VID CurrM "); }

			if (top->mem_addr == 0x033005a0) { fprintf(logfile, "MADAM currentccb"); } // CELControl
			if (top->mem_addr == 0x033005a4) { fprintf(logfile, "MADAM FirstCCB  "); }
			if (top->mem_addr == 0x033005a8) { fprintf(logfile, "MADAM CL PLUT   "); }
			if (top->mem_addr == 0x033005ac) { fprintf(logfile, "MADAM CL DStart "); }

			if (top->mem_addr == 0x033005b0) { fprintf(logfile, "MADAM engafetch "); } // CELData
			if (top->mem_addr == 0x033005b4) { fprintf(logfile, "MADAM engalen   "); }
			if (top->mem_addr == 0x033005b8) { fprintf(logfile, "MADAM engbfetch "); }
			if (top->mem_addr == 0x033005bc) { fprintf(logfile, "MADAM engblen   "); }

			if (top->mem_addr == 0x033005c0) { fprintf(logfile, "MADAM DMA21 Adr "); } // Commandgrabber
			if (top->mem_addr == 0x033005c4) { fprintf(logfile, "MADAM DMA21 Len "); }
			if (top->mem_addr == 0x033005c8) { fprintf(logfile, "MADAM DMA21 NAd "); }
			if (top->mem_addr == 0x033005cc) { fprintf(logfile, "MADAM DMA21 NLn "); }

			if (top->mem_addr == 0x033005d0) { fprintf(logfile, "MADAM DMA22 Adr "); } // Framegrabber
			if (top->mem_addr == 0x033005d4) { fprintf(logfile, "MADAM DMA22 Len "); }
			if (top->mem_addr == 0x033005d8) { fprintf(logfile, "MADAM DMA22 NAd "); }
			if (top->mem_addr == 0x033005dc) { fprintf(logfile, "MADAM DMA22 NLn "); }

			if (top->mem_addr >= 0x03300600 && top->mem_addr <= 0x0330063f) { fprintf(logfile, "MADAM Matrix    "); }
			if (top->mem_addr >= 0x03300640 && top->mem_addr <= 0x0330069c) { fprintf(logfile, "MADAM B0_B1     "); }

			if (top->mem_addr == 0x033006a0) { fprintf(logfile, "MADAM Rsrvd 6a0 "); }
			if (top->mem_addr == 0x03300700) { fprintf(logfile, "MADAM Rsrvd 700 "); }

			if (top->mem_addr == 0x033007f0) { fprintf(logfile, "MADAM Math Set  "); }
			if (top->mem_addr == 0x033007f4) { fprintf(logfile, "MADAM Math Clr  "); }
			if (top->mem_addr == 0x033007f8) { fprintf(logfile, "MADAM Math Stat "); }
			if (top->mem_addr == 0x033007fc) { fprintf(logfile, "MADAM Math Start"); }

			// CLIO...
			if (top->mem_addr == 0x03400000) { fprintf(logfile, "CLIO Revision   "); }
			if (top->mem_addr == 0x03400004) { fprintf(logfile, "CLIO csysbits   "); }
			if (top->mem_addr == 0x03400008) { fprintf(logfile, "CLIO vint0      "); }
			if (top->mem_addr == 0x0340000C) { fprintf(logfile, "CLIO vint1      "); }
			if (top->mem_addr == 0x03400024) { fprintf(logfile, "CLIO audout     "); }
			if (top->mem_addr == 0x03400028) { fprintf(logfile, "CLIO cstatbits  "); }
			if (top->mem_addr == 0x0340002C) { fprintf(logfile, "CLIO WatchDog   "); }
			//if (top->mem_addr == 0x03400034) { fprintf(logfile, "CLIO vcnt       "); }
			if (top->mem_addr == 0x03400038) { fprintf(logfile, "CLIO RandSeed   "); }

			if (top->mem_addr == 0x0340003c) { fprintf(logfile, "CLIO RandSample?"); top->i_wb_dat = 0x00000000; }

			if (top->mem_addr == 0x03400040 && top->o_wb_we) { fprintf(logfile, "CLIO irq0 set   "); }
			if (top->mem_addr == 0x03400044 && top->o_wb_we) { fprintf(logfile, "CLIO irq0 clear "); }
			if (top->mem_addr == 0x03400048 && top->o_wb_we) { fprintf(logfile, "CLIO mask0 set  "); }
			if (top->mem_addr == 0x0340004c && top->o_wb_we) { fprintf(logfile, "CLIO mask0 clear"); }
			if (top->mem_addr == 0x03400040 && !top->o_wb_we) { fprintf(logfile, "CLIO irq0 pend  "); }
			if (top->mem_addr == 0x03400044 && !top->o_wb_we) { fprintf(logfile, "CLIO irq0 pend  "); }
			if (top->mem_addr == 0x03400048 && !top->o_wb_we) { fprintf(logfile, "CLIO mask0 read "); }
			if (top->mem_addr == 0x0340004c && !top->o_wb_we) { fprintf(logfile, "CLIO mask0 read "); }

			if (top->mem_addr == 0x03400050 && top->o_wb_we) { fprintf(logfile, "CLIO SetMode    "); }
			if (top->mem_addr == 0x03400054 && top->o_wb_we) { fprintf(logfile, "CLIO ClrMode    "); }
			if (top->mem_addr == 0x03400058 && top->o_wb_we) { fprintf(logfile, "CLIO BadBits    "); }
			if (top->mem_addr == 0x0340005c && top->o_wb_we) { fprintf(logfile, "CLIO Spare      "); }

			if (top->mem_addr == 0x03400060 && top->o_wb_we) { fprintf(logfile, "CLIO irq1 set   "); }
			if (top->mem_addr == 0x03400064 && top->o_wb_we) { fprintf(logfile, "CLIO irq1 clear "); }
			if (top->mem_addr == 0x03400068 && top->o_wb_we) { fprintf(logfile, "CLIO mask1 set  "); }
			if (top->mem_addr == 0x0340006c && top->o_wb_we) { fprintf(logfile, "CLIO mask1 clear"); }
			if (top->mem_addr == 0x03400060 && !top->o_wb_we) { fprintf(logfile, "CLIO irq1 pend  "); }
			if (top->mem_addr == 0x03400064 && !top->o_wb_we) { fprintf(logfile, "CLIO irq1 pend  "); }
			if (top->mem_addr == 0x03400068 && !top->o_wb_we) { fprintf(logfile, "CLIO mask1 read "); }
			if (top->mem_addr == 0x0340006c && !top->o_wb_we) { fprintf(logfile, "CLIO mask1 read "); }

			if (top->mem_addr == 0x03400080) { fprintf(logfile, "CLIO hdelay     "); }
			if (top->mem_addr == 0x03400084 && !top->o_wb_we) { fprintf(logfile, "CLIO adbio      "); }
			if (top->mem_addr == 0x03400084 && top->o_wb_we) { fprintf(logfile, "CLIO adbio      "); rom2_select = (top->o_wb_dat & 0x04); handle_adbio_write(); }
			if (top->mem_addr == 0x03400088) { fprintf(logfile, "CLIO adbctl     "); }

			if (top->mem_addr == 0x03400100) { fprintf(logfile, "CLIO tmr_cnt_0  "); }
			if (top->mem_addr == 0x03400108) { fprintf(logfile, "CLIO tmr_cnt_1  "); }
			if (top->mem_addr == 0x03400110) { fprintf(logfile, "CLIO tmr_cnt_2  "); }
			if (top->mem_addr == 0x03400118) { fprintf(logfile, "CLIO tmr_cnt_3  "); }
			if (top->mem_addr == 0x03400120) { fprintf(logfile, "CLIO tmr_cnt_4  "); }
			if (top->mem_addr == 0x03400128) { fprintf(logfile, "CLIO tmr_cnt_5  "); }
			if (top->mem_addr == 0x03400130) { fprintf(logfile, "CLIO tmr_cnt_6  "); }
			if (top->mem_addr == 0x03400138) { fprintf(logfile, "CLIO tmr_cnt_7  "); }
			if (top->mem_addr == 0x03400140) { fprintf(logfile, "CLIO tmr_cnt_8  "); }
			if (top->mem_addr == 0x03400148) { fprintf(logfile, "CLIO tmr_cnt_9  "); }
			if (top->mem_addr == 0x03400150) { fprintf(logfile, "CLIO tmr_cnt_10 "); }
			if (top->mem_addr == 0x03400158) { fprintf(logfile, "CLIO tmr_cnt_11 "); }
			if (top->mem_addr == 0x03400160) { fprintf(logfile, "CLIO tmr_cnt_12 "); }
			if (top->mem_addr == 0x03400168) { fprintf(logfile, "CLIO tmr_cnt_13 "); }
			if (top->mem_addr == 0x03400170) { fprintf(logfile, "CLIO tmr_cnt_14 "); }
			if (top->mem_addr == 0x03400178) { fprintf(logfile, "CLIO tmr_cnt_15 "); }

			if (top->mem_addr == 0x03400104) { fprintf(logfile, "CLIO tmr_bkp_0  "); }
			if (top->mem_addr == 0x0340010c) { fprintf(logfile, "CLIO tmr_bkp_1  "); }
			if (top->mem_addr == 0x03400114) { fprintf(logfile, "CLIO tmr_bkp_2  "); }
			if (top->mem_addr == 0x0340011c) { fprintf(logfile, "CLIO tmr_bkp_3  "); }
			if (top->mem_addr == 0x03400124) { fprintf(logfile, "CLIO tmr_bkp_4  "); }
			if (top->mem_addr == 0x0340012c) { fprintf(logfile, "CLIO tmr_bkp_5  "); }
			if (top->mem_addr == 0x03400134) { fprintf(logfile, "CLIO tmr_bkp_6  "); }
			if (top->mem_addr == 0x0340013c) { fprintf(logfile, "CLIO tmr_bkp_7  "); }
			if (top->mem_addr == 0x03400144) { fprintf(logfile, "CLIO tmr_bkp_8  "); }
			if (top->mem_addr == 0x0340014c) { fprintf(logfile, "CLIO tmr_bkp_9  "); }
			if (top->mem_addr == 0x03400154) { fprintf(logfile, "CLIO tmr_bkp_10 "); }
			if (top->mem_addr == 0x0340015c) { fprintf(logfile, "CLIO tmr_bkp_11 "); }
			if (top->mem_addr == 0x03400164) { fprintf(logfile, "CLIO tmr_bkp_12 "); }
			if (top->mem_addr == 0x0340016c) { fprintf(logfile, "CLIO tmr_bkp_13 "); }
			if (top->mem_addr == 0x03400174) { fprintf(logfile, "CLIO tmr_bkp_14 "); }
			if (top->mem_addr == 0x0340017c) { fprintf(logfile, "CLIO tmr_bkp_15 "); }

			if (top->mem_addr == 0x03400200) { fprintf(logfile, "CLIO tmr_set_l  "); }
			if (top->mem_addr == 0x03400204) { fprintf(logfile, "CLIO tmr_clr_l  "); }
			if (top->mem_addr == 0x03400208) { fprintf(logfile, "CLIO tmr_set_u  "); }
			if (top->mem_addr == 0x0340020C) { fprintf(logfile, "CLIO tmr_clr_u  "); }

			if (top->mem_addr == 0x03400220) { fprintf(logfile, "CLIO TmrSlack   "); }
			if (top->mem_addr == 0x03400304 && !top->o_wb_we) { fprintf(logfile, "CLIO dmactrl    "); }
			if (top->mem_addr == 0x03400304 && top->o_wb_we) { fprintf(logfile, "CLIO dmactrl    "); sim_clio_handle_dma(top->o_wb_dat); }
			if (top->mem_addr == 0x03400308) { fprintf(logfile, "CLIO ClrDMAEna  "); }

			if (top->mem_addr == 0x03400380) { fprintf(logfile, "CLIO DMA DSPP0  "); }
			if (top->mem_addr == 0x03400384) { fprintf(logfile, "CLIO DMA DSPP1  "); }
			if (top->mem_addr == 0x03400388) { fprintf(logfile, "CLIO DMA DSPP2  "); }
			if (top->mem_addr == 0x0340038c) { fprintf(logfile, "CLIO DMA DSPP3  "); }
			if (top->mem_addr == 0x03400390) { fprintf(logfile, "CLIO DMA DSPP4  "); }
			if (top->mem_addr == 0x03400394) { fprintf(logfile, "CLIO DMA DSPP5  "); }
			if (top->mem_addr == 0x03400398) { fprintf(logfile, "CLIO DMA DSPP6  "); }
			if (top->mem_addr == 0x0340039c) { fprintf(logfile, "CLIO DMA DSPP7  "); }
			if (top->mem_addr == 0x034003a0) { fprintf(logfile, "CLIO DMA DSPP8  "); }
			if (top->mem_addr == 0x034003a4) { fprintf(logfile, "CLIO DMA DSPP9  "); }
			if (top->mem_addr == 0x034003a8) { fprintf(logfile, "CLIO DMA DSPP10 "); }
			if (top->mem_addr == 0x034003ac) { fprintf(logfile, "CLIO DMA DSPP11 "); }
			if (top->mem_addr == 0x034003b0) { fprintf(logfile, "CLIO DMA DSPP12 "); }
			if (top->mem_addr == 0x034003b4) { fprintf(logfile, "CLIO DMA DSPP13 "); }
			if (top->mem_addr == 0x034003b8) { fprintf(logfile, "CLIO DMA DSPP14 "); }
			if (top->mem_addr == 0x034003bc) { fprintf(logfile, "CLIO DMA DSPP15 "); }

			if (top->mem_addr == 0x034003c0) { fprintf(logfile, "CLIO DSPP DMA0  "); }
			if (top->mem_addr == 0x034003c4) { fprintf(logfile, "CLIO DSPP DMA1  "); }
			if (top->mem_addr == 0x034003c8) { fprintf(logfile, "CLIO DSPP DMA2  "); }
			if (top->mem_addr == 0x034003cc) { fprintf(logfile, "CLIO DSPP DMA3  "); }
			if (top->mem_addr == 0x034003d0) { fprintf(logfile, "CLIO DSPP DMA4  "); }
			if (top->mem_addr == 0x034003d4) { fprintf(logfile, "CLIO DSPP DMA5  "); }
			if (top->mem_addr == 0x034003d8) { fprintf(logfile, "CLIO DSPP DMA6  "); }
			if (top->mem_addr == 0x034003dc) { fprintf(logfile, "CLIO DSPP DMA7  "); }
			if (top->mem_addr == 0x034003e0) { fprintf(logfile, "CLIO DSPP DMA8  "); }
			if (top->mem_addr == 0x034003e4) { fprintf(logfile, "CLIO DSPP DMA9  "); }
			if (top->mem_addr == 0x034003e8) { fprintf(logfile, "CLIO DSPP DMA10 "); }
			if (top->mem_addr == 0x034003ec) { fprintf(logfile, "CLIO DSPP DMA11 "); }
			if (top->mem_addr == 0x034003f0) { fprintf(logfile, "CLIO DSPP DMA12 "); }
			if (top->mem_addr == 0x034003f4) { fprintf(logfile, "CLIO DSPP DMA13 "); }
			if (top->mem_addr == 0x034003f8) { fprintf(logfile, "CLIO DSPP DMA14 "); }
			if (top->mem_addr == 0x034003fc) { fprintf(logfile, "CLIO DSPP DMA15 "); }

			if (top->mem_addr == 0x03400400) { fprintf(logfile, "CLIO expctl_set "); }
			if (top->mem_addr == 0x03400404) { fprintf(logfile, "CLIO expctl_clr "); }
			if (top->mem_addr == 0x03400408) { fprintf(logfile, "CLIO type0_4    "); }
			if (top->mem_addr == 0x03400410) { fprintf(logfile, "CLIO dipir1     "); }
			if (top->mem_addr == 0x03400414) { fprintf(logfile, "CLIO dipir2     "); top->i_wb_dat = 0x4000; }	// TO CHECK!!! requested by CDROMDIPIR.

			// Handle Xbus reads...
			//if (top->mem_addr == 0x03400400) top->i_wb_dat = /*top->rootp->core_3do__DOT__clio_inst__DOT__expctl*/ 0x00000080;
			if ((top->mem_addr >= 0x03400500) && (top->mem_addr <= 0x0340053f) && !top->o_wb_we) { fprintf(logfile, "CLIO sel        "); top->i_wb_dat = sim_xbus_get_res(); }
			if ((top->mem_addr >= 0x03400540) && (top->mem_addr <= 0x0340057f) && !top->o_wb_we) { fprintf(logfile, "CLIO poll       "); top->i_wb_dat = sim_xbus_get_poll(); }
			if ((top->mem_addr >= 0x03400580) && (top->mem_addr <= 0x034005bf) && !top->o_wb_we) { fprintf(logfile, "CLIO CmdStFIFO  "); top->i_wb_dat = sim_xbus_fifo_get_status(); }
			if ((top->mem_addr >= 0x034005C0) && (top->mem_addr <= 0x034005ff) && !top->o_wb_we) { fprintf(logfile, "CLIO Data FIFO  "); top->i_wb_dat = sim_xbus_fifo_get_data(); }

			// DSP...
			if (top->mem_addr == 0x034017d0) { fprintf(logfile, "CLIO sema       "); }
			if (top->mem_addr == 0x034017d4) { fprintf(logfile, "CLIO semaack    "); }
			if (top->mem_addr == 0x034017e0) { fprintf(logfile, "CLIO dspdma     "); }
			if (top->mem_addr == 0x034017e4) { fprintf(logfile, "CLIO dspprst0   "); }
			if (top->mem_addr == 0x034017e8) { fprintf(logfile, "CLIO dspprst1   "); }

			if (top->mem_addr == 0x034017f0) { fprintf(logfile, "CLIO fastrand   "); }

			if (top->mem_addr == 0x034017f4) { fprintf(logfile, "CLIO dspppc     "); }
			if (top->mem_addr == 0x034017f8) { fprintf(logfile, "CLIO dsppnr     "); }
			if (top->mem_addr == 0x034017fc) { fprintf(logfile, "CLIO dsppgw     "); }
			if (top->mem_addr == 0x034039dc) { fprintf(logfile, "CLIO dsppclkreload"); }

			if (top->mem_addr >= 0x03401800 && top->mem_addr <= 0x03401fff) { fprintf(logfile, "CLIO DSPP  N 32 "); }
			if (top->mem_addr >= 0x03402000 && top->mem_addr <= 0x03402fff) { fprintf(logfile, "CLIO DSPP  N 16 "); }
			if (top->mem_addr >= 0x03403000 && top->mem_addr <= 0x034031ff) { fprintf(logfile, "CLIO DSPP EI 32 "); }
			if (top->mem_addr >= 0x03403400 && top->mem_addr <= 0x034037ff) { fprintf(logfile, "CLIO DSPP EI 16 "); }

			// Uncle spoofing stuff handled in clio.v now. ElectronAsh...
			if (top->mem_addr == 0x0340C000) { fprintf(logfile, "CLIO unc_rev    "); }
			if (top->mem_addr == 0x0340C004) { fprintf(logfile, "CLIO unc_soft_rv"); }
			if (top->mem_addr == 0x0340C008) { fprintf(logfile, "CLIO unc_addr   "); }
			if (top->mem_addr == 0x0340C00c) { fprintf(logfile, "CLIO unc_rom    "); }

			//else { fprintf(logfile, "UNKNOWN ?? Addr: 0x%08X  o_wb_we: %d\n", top->mem_addr, top->o_wb_we); top->i_wb_dat = 0xBADACCE5; }

			/*
			uint32_t zap_din = top->rootp->core_3do__DOT__zap_top_inst__DOT__i_wb_dat;
			if ((top->mem_addr >= 0x03100000 && top->mem_addr <= 0x034fffff && top->mem_addr != 0x03400034) ) {
				if (top->o_wb_we) fprintf(logfile, "Write: 0x%08X  (PC: 0x%08X)\n", top->o_wb_dat, cur_pc);
				else fprintf(logfile, " Read: 0x%08X  (PC: 0x%08X)\n", zap_din, cur_pc);
			}
			*/
		}

		if (top->rootp->core_3do__DOT__clio_inst__DOT__vcnt == top->rootp->core_3do__DOT__clio_inst__DOT__vcnt_max && top->rootp->core_3do__DOT__clio_inst__DOT__hcnt==0) {
			frame_count++;
			fprintf(logfile, "frame: %d\n", frame_count);
		}

		if ( (top->rootp->core_3do__DOT__clio_inst__DOT__vcnt & 0x7)==0 && top->rootp->core_3do__DOT__clio_inst__DOT__hcnt == 0) {
		//if ( top->rootp->core_3do__DOT__clio_inst__DOT__vcnt==0 && top->rootp->core_3do__DOT__clio_inst__DOT__hcnt == 0 && top->rootp->core_3do__DOT__clio_inst__DOT__field==0) {
			sim_process_vdl();
			opera_process_vdl();
		}
		
		//if (top->mem_addr==0x03400178 && top->o_wb_we) run_enable = 0;
		//if (top->mem_addr== 0x03400580 && top->o_wb_we && top->o_wb_dat==0x00000010) run_enable = 0;
		//if (cur_pc== 0x000014A8) run_enable = 0;

		//if (top->mem_addr == 0x03300100 && top->o_wb_we) run_enable = 0;	// Stop on write to CEL SPRSTRT.

		/*
		if (old_fiq_n == 1 && top->rootp->core_3do__DOT__clio_inst__DOT__firq_n == 0) { // firq_n falling edge.
			fprintf(logfile, "FIQ triggered!  (PC: 0x%08X)  irq0_pend: 0x%08X  irq1_pend: 0x%08X\n", cur_pc, top->rootp->core_3do__DOT__clio_inst__DOT__irq0_pend, top->rootp->core_3do__DOT__clio_inst__DOT__irq1_pend);
		}
		old_fiq_n = top->rootp->core_3do__DOT__clio_inst__DOT__firq_n;

		uint32_t instruction = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__u_zap_decode__DOT__i_instruction;
		if ( ((instruction & 0xF000000)>>24 == 0b1111) && top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__u_zap_decode__DOT__i_instruction_valid) {
			fprintf(logfile, "SWI 0x%08X  (PC: 0x%08X)\n", instruction, cur_pc);
			//run_enable = 0;
		}
		*/

		if (sim_xbus_fiq_request) {
			sim_xbus_fiq_request = 0;
			top->rootp->core_3do__DOT__clio_inst__DOT__irq0_pend |= (1<<2);	// Set irq0_pend, bit 2. (XBUs IRQ).
		}

		top->sys_clk = 0;
		top->eval();

		uint32_t zap_din = top->rootp->core_3do__DOT__zap_top_inst__DOT__i_wb_dat;
		if ((top->mem_addr >= 0x03100000 && top->mem_addr <= 0x034fffff && top->mem_addr != 0x03400034) && top->o_wb_stb && top->i_wb_ack) {
			if (top->o_wb_we) fprintf(logfile, "Write: 0x%08X  (PC: 0x%08X)\n", top->o_wb_dat, cur_pc);
			else fprintf(logfile, " Read: 0x%08X  (PC: 0x%08X)\n", zap_din, cur_pc);
		}

		if (top->rootp->core_3do__DOT__madam_inst__DOT__mctl & 0x8000) pbus_dma();

		top->sys_clk = 1;
		top->eval();

		return 1;
	}

	// Stop Verilating...
	top->final();
	delete top;
	exit(0);
	return 0;
}

/*
When reading, the states of the bits of the interrupt sources (flags) are read, by writing the bits are equal to 1
set the corresponding bits of the interrupt flags to 1. Apparently this can be simulated
software hardware interrupt.
Interrupt sources with higher numbers have higher priority (implemented in software in
interrupt handler).
VINT0 goes every even half-frame, and VINT1 every odd one (this is the very beginning of the quenching pulse).
bit 00 - VINT0
bit 01 - VINT1 (VSyncTimerFirq, ControlPort, SPORTfirq, GraphicsFirq is hung here)
bit 02 - EXINT (interrupt from devices on XBUS, i.e. for example from CDROM)
bit 03: Timer0.15 Interrupts from timers, only possible from odd (highest in pairs)
bit 04: Timer0.13
bit 05: Timer0.11
bit 06: Timer0.9
bit 07: Timer0.7
bit 08: Timer0.5
bit 09: Timer0.3
bit 10: Timer0.1
bit 11: AudioTimer
bit 12: AudioDMA_DSPtoRAM0
bit 13: AudioDMA_DSPtoRAM1
bit 14: AudioDMA_DSPtoRAM2
bit 15: AudioDMA_DSPtoRAM3
bit 16: AudioDMA_DSPfromRAM0
bit 17: AudioDMA_DSPfromRAM1
bit 18: AudioDMA_DSPfromRAM2
bit 19: AudioDMA_DSPfromRAM3
bit 20: AudioDMA_DSPfromRAM4
bit 21: AudioDMA_DSPfromRAM5
bit 22: AudioDMA_DSPfromRAM6
bit 23: AudioDMA_DSPfromRAM7
bit 24: AudioDMA_DSPfromRAM8
bit 25: AudioDMA_DSPfromRAM9
bit 26: AudioDMA_DSPfromRAM10
bit 27: AudioDMA_DSPfromRAM11
bit 28: AudioDMA_DSPfromRAM12
bit 29: XBUS DMA transfer complete
bit 30: ??? An empty handler - possibly even a watchdog (if that interrupt is enabled and re-triggered). came, and the previous one was not processed, then reset, huh?)
bit 31 - Indicates that there are more interrupts in register 0x0340 0060
*/

static MemoryEditor mem_edit_1;
static MemoryEditor mem_edit_2;
static MemoryEditor mem_edit_3;
static MemoryEditor mem_edit_4;

static MemoryEditor mem_edit_5;
static MemoryEditor mem_edit_6;

int main(int argc, char** argv, char** env) {
	Verilated::traceEverOn(true);
	VerilatedVcdC* m_trace = new VerilatedVcdC;
	top->trace(m_trace, 99);
	m_trace->open("F:\\waveform.vcd");

	// Create application window
	WNDCLASSEX wc = { sizeof(WNDCLASSEX), CS_CLASSDC, WndProc, 0L, 0L, GetModuleHandle(NULL), NULL, NULL, NULL, NULL, _T("ImGui Example"), NULL };
	RegisterClassEx(&wc);
	HWND hwnd = CreateWindow(wc.lpszClassName, _T("Dear ImGui DirectX11 Example"), WS_OVERLAPPEDWINDOW, 100, 100, 1280, 800, NULL, NULL, wc.hInstance, NULL);

	// Initialize Direct3D
	if (CreateDeviceD3D(hwnd) < 0)
	{
		CleanupDeviceD3D();
		UnregisterClass(wc.lpszClassName, wc.hInstance);
		return 1;
	}

	// Show the window
	ShowWindow(hwnd, SW_SHOWMAXIMIZED);
	UpdateWindow(hwnd);

	//system("bash --verbose cd /mnt/c/linux_temp/sim_3do | ls");

	// Setup Dear ImGui context
	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO(); (void)io;
	//io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;  // Enable Keyboard Controls

	// Setup Dear ImGui style
	ImGui::StyleColorsDark();
	//ImGui::StyleColorsClassic();

	// Setup Platform/Renderer bindings
	ImGui_ImplWin32_Init(hwnd);
	ImGui_ImplDX11_Init(g_pd3dDevice, g_pd3dDeviceContext);

	// Load Fonts
	// - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use ImGui::PushFont()/PopFont() to select them.
	// - AddFontFromFileTTF() will return the ImFont* so you can store it if you need to select the font among multiple.
	// - If the file cannot be loaded, the function will return NULL. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
	// - The fonts will be rasterized at a given size (w/ oversampling) and stored into a texture when calling ImFontAtlas::Build()/GetTexDataAsXXXX(), which ImGui_ImplXXXX_NewFrame below will call.
	// - Read 'misc/fonts/README.txt' for more instructions and details.
	// - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !
	//io.Fonts->AddFontDefault();
	//io.Fonts->AddFontFromFileTTF("../../misc/fonts/Roboto-Medium.ttf", 16.0f);
	//io.Fonts->AddFontFromFileTTF("../../misc/fonts/Cousine-Regular.ttf", 15.0f);
	//io.Fonts->AddFontFromFileTTF("../../misc/fonts/DroidSans.ttf", 16.0f);
	//io.Fonts->AddFontFromFileTTF("../../misc/fonts/ProggyTiny.ttf", 10.0f);
	//ImFont* font = io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf", 18.0f, NULL, io.Fonts->GetGlyphRangesJapanese());
	//IM_ASSERT(font != NULL);


	Verilated::commandArgs(argc, argv);

	//memset(rom_ptr, 0x00, rom_size);
	memset(ram_ptr, 0x00, ram_size);
	memset(vram_ptr, 0x00000000, vram_size);
	memset(nvram_ptr, 0x00, nvram_size);

	memset(disp_ptr, 0xff444444, disp_size);
	memset(disp2_ptr, 0xff444444, disp2_size);

	//memset(vga_ptr,  0xAA, vga_size);

	// TESTING!! Load a RAM Dump, so we can test the CEL engine stuff etc.
	//ramdump = fopen("ramdump.bin", "rb");
	//fread(ram_ptr, 1, ram_size, ramdump);

	logfile = fopen("sim_trace.txt", "w");
	inst_file = fopen("sim_inst_trace.txt", "w");

	soundfile = fopen("soundfile.bin", "wb");

	/*
	cel_file = fopen("coded_packed_6bpp.cel", "rb");
	//cel_file = fopen("coded_unpacked_6bpp.cel", "rb");
	fseek(cel_file, 0L, SEEK_END);
	cel_size = ftell(cel_file);
	fseek(cel_file, 0L, SEEK_SET);
	fread(ram_ptr+0, 1, cel_size, cel_file);
	*/

	//isofile = fopen("aitd_us.iso", "rb");
	//isofile = fopen("StarBlade.iso", "rb");
	isofile = fopen("3DentrO.iso", "rb");
	//isofile = fopen("3DO teaser trailer 25% ISO.iso", "rb");
	//isofile = fopen("3DO Homebrew pack #1.iso", "rb");
	//isofile = fopen("stniccc_3do_4bpp.iso", "rb");
	//isofile = fopen("optidoom_02c.iso", "rb");
	//CDIMAGE_SECTOR_SIZE = 2352; isofile = fopen("nfs_usa.bin", "rb");			// 2352-byte sectors!
	//isofile = fopen("PhotoCD_Gallery.iso", "rb");
	fseek(isofile, 0L, SEEK_END);
	
	fseek(isofile, 0L, SEEK_SET);


	FILE* romfile;
	//romfile = fopen("panafz1.bin", "rb");
	romfile = fopen("panafz10.bin", "rb");			// This is the version MAME v226b uses by default, with "mame64 3do".
	//romfile = fopen("panafz10-norsa.bin", "rb");
	//romfile = fopen("sanyotry.bin", "rb");
	//romfile = fopen("goldstar.bin", "rb");
	//if (romfile != NULL) { sprintf(my_string, "\nBIOS file loaded OK.\n");  MyAddLog(my_string); }
	//else { sprintf(my_string, "\nBIOS file not found!\n\n"); MyAddLog(my_string); return 0; }
	//unsigned int file_size;
	fseek(romfile, 0L, SEEK_END);
	file_size = ftell(romfile);
	fseek(romfile, 0L, SEEK_SET);
	fread(rom_ptr, 1, rom_size, romfile);   // Read the whole BIOS file into RAM.

	FILE* rom2file;
	rom2file = fopen("panafz1-kanji.bin", "rb");
	//if (rom2file != NULL) { sprintf(my_string, "\nBIOS file loaded OK.\n");  MyAddLog(my_string); }
	//else { sprintf(my_string, "\nBIOS file not found!\n\n"); MyAddLog(my_string); return 0; }
	//unsigned int file_size;
	fseek(rom2file, 0L, SEEK_END);
	file_size = ftell(rom2file);
	fseek(rom2file, 0L, SEEK_SET);
	fread(rom2_ptr, 1, rom2_size, rom2file);        // Read the whole BIOS file into RAM.

	/*
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI00_in = 0x8002aabb;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI01_in = 0xf00cc243;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI02_in = 0x2222aabb;

	top->rootp->core_3do__DOT__matrix_inst__DOT__MI10_in = 0x44333333;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI11_in = 0xF000aabb;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI11_in = 0x00045226;

	top->rootp->core_3do__DOT__matrix_inst__DOT__MI20_in = 0xc0084526;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI21_in = 0x0000007e;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI22_in = 0x000c000c;

	top->rootp->core_3do__DOT__matrix_inst__DOT__MV0_in = 0x00000888;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MV1_in = 0x44880000;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MV2_in = 0x00444444;
	*/

	// Our state
	bool show_demo_window = true;
	bool show_another_window = false;
	ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

	// Build texture atlas
	int width = 320;
	int height = 263;

	// Upload texture to graphics system
	D3D11_TEXTURE2D_DESC desc;
	ZeroMemory(&desc, sizeof(desc));
	desc.Width = width;
	desc.Height = height;
	desc.MipLevels = 1;
	desc.ArraySize = 1;
	desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	desc.SampleDesc.Count = 1;
	desc.Usage = D3D11_USAGE_DEFAULT;
	desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

	ID3D11Texture2D* pTexture = NULL;
	D3D11_SUBRESOURCE_DATA subResource;
	subResource.pSysMem = disp_ptr;
	//subResource.pSysMem = vga_ptr;
	subResource.SysMemPitch = desc.Width * 4;
	subResource.SysMemSlicePitch = 0;
	g_pd3dDevice->CreateTexture2D(&desc, &subResource, &pTexture);

	// Create texture view
	D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc;
	ZeroMemory(&srvDesc, sizeof(srvDesc));
	srvDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
	srvDesc.Texture2D.MipLevels = desc.MipLevels;
	srvDesc.Texture2D.MostDetailedMip = 0;
	g_pd3dDevice->CreateShaderResourceView(pTexture, &srvDesc, &g_pFontTextureView);
	pTexture->Release();

	// Store our identifier
	ImTextureID my_tex_id = (ImTextureID)g_pFontTextureView;

	// Create texture sampler
	{
		D3D11_SAMPLER_DESC desc;
		ZeroMemory(&desc, sizeof(desc));
		//desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;        // LERP.
		//desc.Filter = D3D11_FILTER_ANISOTROPIC;
		desc.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;         // Point sampling.
		desc.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
		desc.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
		desc.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
		desc.MipLODBias = 0.f;
		desc.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
		desc.MinLOD = 0.f;
		desc.MaxLOD = 0.f;
		g_pd3dDevice->CreateSamplerState(&desc, &g_pFontSampler);
	}



	// Upload texture to graphics system
	D3D11_TEXTURE2D_DESC desc2;
	ZeroMemory(&desc2, sizeof(desc2));
	desc2.Width = width;
	desc2.Height = height;
	desc2.MipLevels = 1;
	desc2.ArraySize = 1;
	desc2.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	desc2.SampleDesc.Count = 1;
	desc2.Usage = D3D11_USAGE_DEFAULT;
	desc2.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	desc2.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

	ID3D11Texture2D* pTexture2 = NULL;
	D3D11_SUBRESOURCE_DATA subResource2;
	subResource2.pSysMem = disp2_ptr;
	//subResource2.pSysMem = g_VIDEO_BUFFER;
	subResource2.SysMemPitch = desc2.Width * 4;
	subResource2.SysMemSlicePitch = 0;
	g_pd3dDevice->CreateTexture2D(&desc2, &subResource2, &pTexture2);

	// Create texture view
	D3D11_SHADER_RESOURCE_VIEW_DESC srvDesc2;
	ZeroMemory(&srvDesc2, sizeof(srvDesc2));
	srvDesc2.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	srvDesc2.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
	srvDesc2.Texture2D.MipLevels = desc.MipLevels;
	srvDesc2.Texture2D.MostDetailedMip = 0;
	g_pd3dDevice->CreateShaderResourceView(pTexture2, &srvDesc2, &g_pFontTextureView2);
	pTexture2->Release();

	// Store our identifier
	ImTextureID my_tex_id2 = (ImTextureID)g_pFontTextureView2;

	// Create texture sampler
	{
		D3D11_SAMPLER_DESC desc2;
		ZeroMemory(&desc2, sizeof(desc2));
		//desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;        // LERP.
		//desc.Filter = D3D11_FILTER_ANISOTROPIC;
		desc2.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;         // Point sampling.
		desc2.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
		desc2.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
		desc2.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
		desc2.MipLODBias = 0.f;
		desc2.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
		desc2.MinLOD = 0.f;
		desc2.MaxLOD = 0.f;
		g_pd3dDevice->CreateSamplerState(&desc2, &g_pFontSampler2);
	}

	static bool show_app_console = true;

	my_opera_init();

	/* select test, use -1 -- if don't need tests */
	sim_diag_port_init(-1);	// Normal BIOS startup.
	//sim_diag_port_init(0xf1);

	opera_diag_port_init(-1);	// Normal BIOS startup.
	//opera_diag_port_init(0xf1);

	/*
	0z00      DIAGNOSTICS TEST (1F,24,25,32,50,51,60,61,62,68,71,75,80,81,90)
	0z01      AUTO-DIAG TEST   (1F,24,25,32,50,51,60,61,62,68,80,81,90)
	0z12      DRAM1 DATA TEST   * ?
	0z1A      DRAM2 DATA TEST
	0z1E      EARLY RAM TEST
	0z1F      RAM DATA TEST     *
	0z22      VRAM1 DATA TEST   *
	0z24      VRAM1 FLASH TEST  *
	0z25      VRAM1 SPORT TEST  *
	0z32      SRAM DATA TEST    *
	0z50      MADAM TEST		*?
	0z51      CLIO TEST			*?
	0z60      CD-ROM POLL TEST
	0z61      CD-ROM PATH TEST
	0z62      CD-ROM READ TEST        ???
	0z63      CD-ROM AutoAdjustValue TEST
	0z67      CD-ROM#2 AutoAdjustValue TEST
	0z68  DEV#15 POLL TEST
	0z71      JOYPAD1 PRESS TEST
	0z75      JOYPAD1 AUDIO TEST
	0z80      SIN WAVE TEST
	0z81      MUTING TEST
	0z90      COLORBAR
	0zF0      CHECK TESTTOOL  ???
	0zF1      REVISION TEST
	0zFF      TEST END (halt)
	*/

	// imgui Main loop stuff...
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT)
	{
		if (PeekMessage(&msg, NULL, 0U, 0U, PM_REMOVE))
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
			continue;
		}

		// Start the Dear ImGui frame
		ImGui_ImplDX11_NewFrame();
		ImGui_ImplWin32_NewFrame();
		ImGui::NewFrame();

		//static float f = 0.1f;
		//static int counter = 0;

		ImGui::Begin("Virtual Dev Board v1.0");		// Create a window called "Virtual Dev Board v1.0" and append into it.

		ShowMyExampleAppConsole(&show_app_console);

		if (ImGui::Button("RESET")) {
			my_opera_init();

			main_time = 0;
			rom2_select = 0;        // Select the BIOS ROM at startup! (not Kanji).
			map_bios = 1;
			trig_irq = 0;
			trig_fiq = 0;
			frame_count = 0;
			line_count = 0;
			memset(disp_ptr, 0xff444444, disp_size);        // Clear the DISPLAY buffer.
			memset(ram_ptr, 0x00, ram_size);                // Clear Main RAM.
			memset(vram_ptr, 0x00000000, vram_size);        // Clear VRAM.
			memset(nvram_ptr, 0x00000000, nvram_size);      // Clear NVRAM (SRAM).
		}
		ImGui::SameLine(); ImGui::Text("main_time %d", main_time);
		ImGui::Text("frame_count: %d  field: %d  hcnt: %04d  vcnt: %d", frame_count, top->rootp->core_3do__DOT__clio_inst__DOT__field, top->rootp->core_3do__DOT__clio_inst__DOT__hcnt, top->rootp->core_3do__DOT__clio_inst__DOT__vcnt);

		ImGui::Checkbox("RUN", &run_enable);

		dump_ram = ImGui::Button("RAM Dump");
		ImGui::SameLine(); ImGui::SliderInt("spr_width", &spr_width, 32, 388);

		if (dump_ram) {
			ramdump = fopen("ramdump.bin", "wb");
			fwrite(ram_ptr, 1, ram_size, ramdump);  // Dump main RAM to a file.
			fclose(ramdump);
		}

		if (single_step == 1) single_step = 0;
		if (ImGui::Button("Single Step")) {
			run_enable = 0;
			single_step = 1;
		}
		ImGui::SameLine();
		if (multi_step == 1) multi_step = 0;
		if (ImGui::Button("Multi Step")) {
			run_enable = 0;
			multi_step = 1;
		}
		ImGui::SameLine(); ImGui::SliderInt("Step amount", &multi_step_amount, 8, 1024);

		ImGui::Separator();
		ImGui::Image(my_tex_id,  ImVec2(width*2, height*2), ImVec2(0, 0), ImVec2(1, 1), ImColor(255, 255, 255, 255), ImColor(255, 255, 255, 128));
		ImGui::SameLine();
		ImGui::Image(my_tex_id2, ImVec2(width/2, height/2), ImVec2(0, 0), ImVec2(1, 1), ImColor(255, 255, 255, 255), ImColor(255, 255, 255, 128));
		ImGui::End();

		ImGui::Begin("3DO BIOS ROM Editor");
		mem_edit_1.DrawContents(rom_ptr, rom_size, 0);
		ImGui::End();

		ImGui::Begin("3DO Main RAM Editor");
		mem_edit_2.DrawContents(ram_ptr, ram_size, 0);
		ImGui::End();

		ImGui::Begin("3DO VRAM Editor");
		mem_edit_3.DrawContents(vram_ptr, vram_size, 0);
		ImGui::End();

		ImGui::Begin("3DO SRAM (NVRAM) Editor");
		mem_edit_4.DrawContents(nvram_ptr, nvram_size, 0);
		ImGui::End();

		ImGui::Begin("Opera DRAM Editor");
		mem_edit_5.DrawContents(dram, ram_size, 0);
		ImGui::End();

		ImGui::Begin("Opera VRAM Editor");
		mem_edit_6.DrawContents(vram, vram_size, 0);
		ImGui::End();

		ImGui::Begin("ARM Registers");

		if ( run_enable==1 ) {
			if (ImGui::IsKeyPressed(ImGuiKey_F10) || ImGui::IsKeyPressed(ImGuiKey_F11) ) run_enable = 0;
		}
		else {
			if ( ImGui::IsKeyPressed(ImGuiKey_F5)  ) run_enable = 1;
			if ( ImGui::IsKeyPressed(ImGuiKey_F10) ) multi_step = 1;
			if ( ImGui::IsKeyPressed(ImGuiKey_F11) ) single_step = 1;
		}

		if (run_enable)
		{
			for (int step = 0; step < 2048; step++)
			{
				/*
				top->sys_clk = 0;
				top->eval();

				if ((frame_count >= MIN_FRAME) && (frame_count <= MAX_FRAME + 1)) {
					m_trace->dump(10 * main_time - 2);
				}

				top->sys_clk = 1;
				top->eval();

				if ((frame_count >= MIN_FRAME) && (frame_count <= MAX_FRAME + 1)) {
					m_trace->dump(10 * main_time);
				}

				top->sys_clk = 0;
				top->eval();

				if ((frame_count >= MIN_FRAME) && (frame_count <= MAX_FRAME + 1)) {
					m_trace->dump(10 * main_time + 5);
					m_trace->flush();
				}
				*/
				
				verilate();
				//opera_tick();
				//if ( (main_time&0xf)==0 ) opera_process_vdl();

				if (run_enable==0) break;
				main_time++;
			}
		}
		
		if (multi_step) {
			for (int i = 0; i < multi_step_amount; i++) {
			/*
				top->sys_clk = 0;
				top->eval();

				if ((frame_count >= MIN_FRAME) && (frame_count <= MAX_FRAME + 1)) {
					m_trace->dump(10 * main_time - 2);
				}

				top->sys_clk = 1;
				top->eval();

				if ((frame_count >= MIN_FRAME) && (frame_count <= MAX_FRAME + 1)) {
					m_trace->dump(10 * main_time);
				}

				top->sys_clk = 0;
				top->eval();
				*/
				verilate();
				//if (run_enable == 0) break;
				main_time++;
			}
		}
		
		if (single_step) {
			/*
			top->sys_clk = 0;
			top->eval();

			if ((frame_count >= MIN_FRAME) && (frame_count <= MAX_FRAME + 1)) {
				m_trace->dump(10 * main_time - 2);
			}

			top->sys_clk = 1;
			top->eval();

			if ((frame_count >= MIN_FRAME) && (frame_count <= MAX_FRAME + 1)) {
				m_trace->dump(10 * main_time);
			}

			top->sys_clk = 0;
			top->eval();
			*/
			verilate();
			main_time++;
		}

		ImGui::Text("    reset_n: %d", top->rootp->core_3do__DOT__reset_n);
		ImGui::Separator();
		ImGui::Text("    dma_ack: %d", top->rootp->core_3do__DOT__madam_inst__DOT__dma_ack);
		ImGui::Text("   mem_addr: 0x%08X", top->mem_addr);
		//ImGui::Text("   o_wb_adr: 0x%08X", top->o_wb_adr);
		ImGui::SameLine();
		if (top->rootp->mem_addr >= 0x00000000 && top->rootp->mem_addr <= 0x001FFFFF) {
			if (map_bios) ImGui::Text("    BIOS (mapped)"); else ImGui::Text("    Main RAM    ");
		}
		else if (top->rootp->mem_addr >= 0x00200000 && top->rootp->mem_addr <= 0x003FFFFF) ImGui::Text("       VRAM      ");
		else if (top->rootp->mem_addr >= 0x03000000 && top->rootp->mem_addr <= 0x030FFFFF) ImGui::Text("       BIOS      ");
		else if (top->rootp->mem_addr >= 0x03100000 && top->rootp->mem_addr <= 0x0313FFFF) ImGui::Text("       Brooktree ");
		else if (top->rootp->mem_addr >= 0x03140000 && top->rootp->mem_addr <= 0x0315FFFF) ImGui::Text("       NVRAM     ");
		else if (top->rootp->mem_addr == 0x03180000) ImGui::Text("       DiagPort  ");
		else if (top->rootp->mem_addr >= 0x03180004 && top->rootp->mem_addr <= 0x031BFFFF) ImGui::Text("    Slow Bus     ");
		else if (top->rootp->mem_addr >= 0x03200000 && top->rootp->mem_addr <= 0x0320FFFF) ImGui::Text("       VRAM SVF  ");
		else if (top->rootp->mem_addr >= 0x03300000 && top->rootp->mem_addr <= 0x033FFFFF) ImGui::Text("       MADAM     ");
		else if (top->rootp->mem_addr >= 0x03400000 && top->rootp->mem_addr <= 0x034FFFFF) ImGui::Text("       CLIO      ");
		else ImGui::Text("    Unknown    ");

		ImGui::Text("   i_wb_dat: 0x%08X", top->i_wb_dat);
		ImGui::Separator();
		ImGui::Text("   o_wb_dat: 0x%08X", top->o_wb_dat);
		ImGui::Text("    o_wb_we: %d", top->o_wb_we); ImGui::SameLine(); if (!top->o_wb_we) ImGui::Text(" Read"); else ImGui::Text(" Write");
		ImGui::Text("   o_wb_sel: 0x%01X", top->o_wb_sel);
		//ImGui::Text("   o_wb_cyc: %d", top->o_wb_cyc);
		ImGui::Text("   o_wb_stb: %d", top->o_wb_stb);
		//ImGui::Text("   i_wb_ack: %d", top->i_wb_ack);
		//ImGui::Text("   o_wb_cti: 0x%01X", top->o_wb_cti);
		//ImGui::Text("   o_wb_bte: 0x%01X", top->o_wb_bte);
		ImGui::Separator();
		ImGui::Text("      i_fiq: %d", top->rootp->core_3do__DOT__zap_top_inst__DOT__i_fiq);


		uint32_t reg_src = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__o_alu_source_ff;
		uint32_t reg_dst = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__o_destination_index_ff;
		ImVec4 reg_col[40];
		for (int i = 0; i < 40; i++) {
			reg_col[i] = ImVec4(1.0f, 1.0f, 1.0f, 1.0f);		// Text defaults to white.
			if (reg_src == i) reg_col[i] = ImVec4(0.0f, 1.0f, 0.0f, 1.0f);       // Source reg = GREEN.
			if (reg_dst == i) reg_col[i] = ImVec4(1.0f, 0.0f, 0.0f, 1.0f);       // Dest reg = RED.
		}

		uint32_t arm_reg[40];
		for (int i = 0; i < 40; i++) {
			arm_reg[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__mem[i];
		}

		//uint32_t cpsr = arm_reg[17]; // PHY_CPSR=17.
		uint32_t cpsr = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__cpsr_ff;

		//if ( cpu_mode==0b10000 )                // User mode
		if ((cpsr&0x1f)==0b10001) reg_col[35] = ImVec4(0.0f, 1.0f, 1.0f, 1.0f);	// FIQ mode
		if ((cpsr&0x1f)==0b10010) reg_col[36] = ImVec4(0.0f, 1.0f, 1.0f, 1.0f);	// IRQ mode
		if ((cpsr&0x1f)==0b10011) reg_col[37] = ImVec4(0.0f, 1.0f, 1.0f, 1.0f);	// Supervisor mode
		if ((cpsr&0x1f)==0b11011) reg_col[38] = ImVec4(0.0f, 1.0f, 1.0f, 1.0f);	// Undefined mode
		if ((cpsr&0x1f)==0b10111) reg_col[39] = ImVec4(0.0f, 1.0f, 1.0f, 1.0f);	// Abort mode
		//if ((cpsr&0x1f)==0b11111 ) reg_col[99] = ImVec4(0.0f, 1.0f, 1.0f, 1.0f);	// System mode

		ImGui::Separator();
		//ImGui::Text("         PC: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_issue_main__DOT__o_pc_ff);  ImGui::SameLine(); ImGui::Text(" Opera  PC: 0x%08X", CPU.USER[15]);
		ImGui::Text("         PC: 0x%08X", cur_pc);  ImGui::SameLine(); ImGui::Text(" Opera  PC: 0x%08X", CPU.USER[15]);
		ImGui::TextColored(ImVec4(reg_col[0]),  "         R0: 0x%08X", arm_reg[0]);  ImGui::SameLine(); ImGui::Text(" Opera  R0: 0x%08X", CPU.USER[0]);
		ImGui::TextColored(ImVec4(reg_col[1]),  "         R1: 0x%08X", arm_reg[1]);  ImGui::SameLine(); ImGui::Text(" Opera  R1: 0x%08X", CPU.USER[1]);
		ImGui::TextColored(ImVec4(reg_col[2]),  "         R2: 0x%08X", arm_reg[2]);  ImGui::SameLine(); ImGui::Text(" Opera  R2: 0x%08X", CPU.USER[2]);
		ImGui::TextColored(ImVec4(reg_col[3]),  "         R3: 0x%08X", arm_reg[3]);  ImGui::SameLine(); ImGui::Text(" Opera  R3: 0x%08X", CPU.USER[3]);
		ImGui::TextColored(ImVec4(reg_col[4]),  "         R4: 0x%08X", arm_reg[4]);  ImGui::SameLine(); ImGui::Text(" Opera  R4: 0x%08X", CPU.USER[4]);
		ImGui::TextColored(ImVec4(reg_col[5]),  "         R5: 0x%08X", arm_reg[5]);  ImGui::SameLine(); ImGui::Text(" Opera  R5: 0x%08X", CPU.USER[5]);
		ImGui::TextColored(ImVec4(reg_col[6]),  "         R6: 0x%08X", arm_reg[6]);  ImGui::SameLine(); ImGui::Text(" Opera  R6: 0x%08X", CPU.USER[6]);
		ImGui::TextColored(ImVec4(reg_col[7]),  "         R7: 0x%08X", arm_reg[7]);  ImGui::SameLine(); ImGui::Text(" Opera  R7: 0x%08X", CPU.USER[7]);

		if ((cpsr&0x1f) == 0b10001) {	// FIQ
			ImGui::TextColored(ImVec4(reg_col[18]), "        FR8: 0x%08X", arm_reg[18]); ImGui::SameLine(); ImGui::Text(" Opera  R8: 0x%08X", CPU.USER[8]);
			ImGui::TextColored(ImVec4(reg_col[19]), "        FR9: 0x%08X", arm_reg[19]); ImGui::SameLine(); ImGui::Text(" Opera  R9: 0x%08X", CPU.USER[9]);
			ImGui::TextColored(ImVec4(reg_col[20]), "       FR10: 0x%08X", arm_reg[20]); ImGui::SameLine(); ImGui::Text(" Opera R10: 0x%08X", CPU.USER[10]);
			ImGui::TextColored(ImVec4(reg_col[21]), "       FR11: 0x%08X", arm_reg[21]); ImGui::SameLine(); ImGui::Text(" Opera R11: 0x%08X", CPU.USER[11]);
			ImGui::TextColored(ImVec4(reg_col[22]), "       FR12: 0x%08X", arm_reg[22]); ImGui::SameLine(); ImGui::Text(" Opera R12: 0x%08X", CPU.USER[12]);
		}
		else {
			ImGui::TextColored(ImVec4(reg_col[8]),  "         R8: 0x%08X", arm_reg[8]);  ImGui::SameLine(); ImGui::Text(" Opera  R8: 0x%08X", CPU.USER[8]);
			ImGui::TextColored(ImVec4(reg_col[9]),  "         R9: 0x%08X", arm_reg[9]);  ImGui::SameLine(); ImGui::Text(" Opera  R9: 0x%08X", CPU.USER[9]);
			ImGui::TextColored(ImVec4(reg_col[10]), "        R10: 0x%08X", arm_reg[10]); ImGui::SameLine(); ImGui::Text(" Opera R10: 0x%08X", CPU.USER[10]);
			ImGui::TextColored(ImVec4(reg_col[11]), "        R11: 0x%08X", arm_reg[11]); ImGui::SameLine(); ImGui::Text(" Opera R11: 0x%08X", CPU.USER[11]);
			ImGui::TextColored(ImVec4(reg_col[12]), "        R12: 0x%08X", arm_reg[12]); ImGui::SameLine(); ImGui::Text(" Opera R12: 0x%08X", CPU.USER[12]);
		}

		switch (cpsr & 0x1f) {	// CPU Mode bits [4:0].
			case 0b10001:	// FIQ.
				ImGui::TextColored(ImVec4(reg_col[23]), "       FR13: 0x%08X", arm_reg[23]); ImGui::SameLine(); ImGui::Text(" Opera R13: 0x%08X", CPU.USER[13]);
				ImGui::TextColored(ImVec4(reg_col[24]), "       FR14: 0x%08X", arm_reg[24]); ImGui::SameLine(); ImGui::Text(" Opera R14: 0x%08X", CPU.USER[14]); 
				/*ImGui::TextColored(ImVec4(reg_col[35]), "   FIQ SPSR: 0x%08X", arm_reg[35]);*/ break;
			case 0b10010: // IRQ.
				ImGui::TextColored(ImVec4(reg_col[25]), "      IRQ13: 0x%08X", arm_reg[25]); ImGui::SameLine(); ImGui::Text(" Opera R13: 0x%08X", CPU.USER[13]);
				ImGui::TextColored(ImVec4(reg_col[26]), "      IRQ14: 0x%08X", arm_reg[26]); ImGui::SameLine(); ImGui::Text(" Opera R14: 0x%08X", CPU.USER[14]);
				/*ImGui::TextColored(ImVec4(reg_col[36]), "   IRQ SPSR: 0x%08X", arm_reg[36]);*/ break;
			case 0b10011: // SVC
				ImGui::TextColored(ImVec4(reg_col[27]), "      SVC13: 0x%08X", arm_reg[27]); ImGui::SameLine(); ImGui::Text(" Opera R13: 0x%08X", CPU.USER[13]);
				ImGui::TextColored(ImVec4(reg_col[28]), "      SVC14: 0x%08X", arm_reg[28]); ImGui::SameLine(); ImGui::Text(" Opera R14: 0x%08X", CPU.USER[14]);
				/*ImGui::TextColored(ImVec4(reg_col[17]), "       CPSR: 0x%08X", cpsr);*/ break;
			case 0b11011: // UND
				ImGui::TextColored(ImVec4(reg_col[29]), "      UND13: 0x%08X", arm_reg[29]); ImGui::SameLine(); ImGui::Text(" Opera R13: 0x%08X", CPU.USER[13]);
				ImGui::TextColored(ImVec4(reg_col[30]), "      UND14: 0x%08X", arm_reg[30]); ImGui::SameLine(); ImGui::Text(" Opera R14: 0x%08X", CPU.USER[14]);
				/*ImGui::TextColored(ImVec4(reg_col[38]), "   UND SPSR: 0x%08X", arm_reg[38]);*/ break;
			case 0b10111: // ABT
				ImGui::TextColored(ImVec4(reg_col[31]), "      ABT13: 0x%08X", arm_reg[31]); ImGui::SameLine(); ImGui::Text(" Opera R13: 0x%08X", CPU.USER[13]);
				ImGui::TextColored(ImVec4(reg_col[32]), "      ABT14: 0x%08X", arm_reg[32]); ImGui::SameLine(); ImGui::Text(" Opera R14: 0x%08X", CPU.USER[14]);
				/*ImGui::TextColored(ImVec4(reg_col[39]), "   ABT SPSR: 0x%08X", arm_reg[39]);*/ break;
			default:	// BAD / USR ??
				ImGui::TextColored(ImVec4(reg_col[13]), "        R13: 0x%08X", arm_reg[13]); ImGui::SameLine(); ImGui::Text(" Opera R13: 0x%08X", CPU.USER[13]);
				ImGui::TextColored(ImVec4(reg_col[14]), "        R14: 0x%08X", arm_reg[14]); ImGui::SameLine(); ImGui::Text(" Opera R14: 0x%08X", CPU.USER[14]);
				/*ImGui::TextColored(ImVec4(reg_col[17]), "       CPSR: 0x%08X", arm_reg[17]);*/ break;
		}

		ImGui::TextColored(ImVec4(reg_col[17]), "       CPSR: 0x%08X", cpsr); ImGui::SameLine(); ImGui::Text("Opera CPSR: 0x%08X", CPU.CPSR);	// BAD / USR ??

		//if (arm_reg[0]==0x100002B5) run_enable = 0;

		/*
		switch (CPU.CPSR & 0x1F) {
			case 0b10001:	// FIQ.
					 break;
			case 0b10010: // IRQ.
					break;
			case 0b10011: // SVC
					ImGui::SameLine(); ImGui::Text("Opera SPSR: 0x%08X", CPU.SPSR); break;
			case 0b11011: // UND
					break;
			case 0b10111: // ABT
					break;
			default: ImGui::SameLine(); ImGui::Text("Opera CPSR: 0x%08X", CPU.CPSR); break;	// BAD / USR ??
		}
		*/

		//ImGui::TextColored(ImVec4(reg_col[15]), " unused? R15: 0x%08X", arm_reg[15]);
		ImGui::Separator();

		ImGui::Text("  CPSR bits: %d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d",
			(cpsr & 0x80000000) >> 31, (cpsr & 0x40000000) >> 30, (cpsr & 0x20000000) >> 29, (cpsr & 0x10000000) >> 28, (cpsr & 0x08000000) >> 27, (cpsr & 0x04000000) >> 26, (cpsr & 0x02000000) >> 25, (cpsr & 0x01000000) >> 24,
			(cpsr & 0x00800000) >> 23, (cpsr & 0x00400000) >> 22, (cpsr & 0x00200000) >> 21, (cpsr & 0x00100000) >> 20, (cpsr & 0x00080000) >> 19, (cpsr & 0x00040000) >> 18, (cpsr & 0x00020000) >> 17, (cpsr & 0x00010000) >> 16,
			(cpsr & 0x00008000) >> 15, (cpsr & 0x00004000) >> 14, (cpsr & 0x00002000) >> 13, (cpsr & 0x00001000) >> 12, (cpsr & 0x00000800) >> 11, (cpsr & 0x00000400) >> 10, (cpsr & 0x00000200) >> 9, (cpsr & 0x00000100) >> 8,
			(cpsr & 0x00000080) >> 7, (cpsr & 0x00000040) >> 6, (cpsr & 0x00000020) >> 5, (cpsr & 0x00000010) >> 4, (cpsr & 0x00000008) >> 3, (cpsr & 0x00000004) >> 2, (cpsr & 0x00000002) >> 1, (cpsr & 0x00000001) >> 0);
		ImGui::Text("             NZCVQIIJ    GGGGIIIIIIEAIFTMMMMM");
		ImGui::Text("                  TT     EEEETTTTTT    ");
		ImGui::SameLine();
			switch (cpsr&0x1f) {
				case 0b00000: ImGui::Text(" BAD "); break;
				case 0b10000: ImGui::Text(" USR "); break;
				case 0b10001: ImGui::Text(" FIQ "); break;
				case 0b10010: ImGui::Text(" IRQ "); break;
				case 0b10011: ImGui::Text(" SVC "); break;
				case 0b11011: ImGui::Text(" UND "); break;
				     default: ImGui::Text("     "); break;
			}
		ImGui::Separator();
		ImGui::Text(" Zap Core decompile");
		ImGui::Text(" 0x%08X: ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__predecode_inst);
		ImGui::Text("     decode: %s", decode_string);
		ImGui::Text("      issue: %s", issue_string);
		ImGui::Text("    shifter: %s", shifter_string);
		ImGui::Text("        alu: %s", alu_string);
		ImGui::Text("     memory: %s", memory_string);
		ImGui::Text("         rb: %s", rb_string);
		ImGui::End();


		ImGui::Begin("ARM Secondary regs");
		ImGui::TextColored(ImVec4(reg_col[18]), "      FR8: 0x%08X", arm_reg[18]);
		ImGui::TextColored(ImVec4(reg_col[19]), "      FR9: 0x%08X", arm_reg[19]);
		ImGui::TextColored(ImVec4(reg_col[20]), "     FR10: 0x%08X", arm_reg[20]);
		ImGui::TextColored(ImVec4(reg_col[21]), "     FR11: 0x%08X", arm_reg[21]);
		ImGui::TextColored(ImVec4(reg_col[22]), "     FR12: 0x%08X", arm_reg[22]);
		ImGui::TextColored(ImVec4(reg_col[23]), "     FR13: 0x%08X", arm_reg[23]);
		ImGui::TextColored(ImVec4(reg_col[24]), "     FR14: 0x%08X", arm_reg[24]);
		ImGui::TextColored(ImVec4(reg_col[35]), " FIQ_SPSR: 0x%08X", arm_reg[35]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[25]), "    IRQ13: 0x%08X", arm_reg[25]);
		ImGui::TextColored(ImVec4(reg_col[26]), "    IRQ14: 0x%08X", arm_reg[26]);
		ImGui::TextColored(ImVec4(reg_col[36]), " IRQ_SPSR: 0x%08X", arm_reg[36]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[27]), "    SVC13: 0x%08X", arm_reg[27]);
		ImGui::TextColored(ImVec4(reg_col[28]), "    SVC14: 0x%08X", arm_reg[28]);
		ImGui::TextColored(ImVec4(reg_col[37]), " SVC_SPSR: 0x%08X", arm_reg[37]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[29]), "    UND13: 0x%08X", arm_reg[29]);
		ImGui::TextColored(ImVec4(reg_col[30]), "    UND14: 0x%08X", arm_reg[30]);
		ImGui::TextColored(ImVec4(reg_col[38]), " UND_SPSR: 0x%08X", arm_reg[38]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[31]), "    ABT13: 0x%08X", arm_reg[31]);
		ImGui::TextColored(ImVec4(reg_col[32]), "    ABT14: 0x%08X", arm_reg[32]);
		ImGui::TextColored(ImVec4(reg_col[39]), " ABT_SPSR: 0x%08X", arm_reg[39]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[33]), "     DUM0: 0x%08X", arm_reg[33]);
		ImGui::TextColored(ImVec4(reg_col[34]), "     DUM1: 0x%08X", arm_reg[34]);
		ImGui::Separator();
		ImGui::End();

		ImGui::Begin("CLIO Registers");
		ImGui::Text("       vint0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__vint0);
		ImGui::Text("       vint1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__vint1);
		ImGui::Separator();
		ImGui::Text("   cstatbits: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__cstatbits);
		ImGui::Text("        wdog: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__wdog);			// 0x2c
		ImGui::Text("        hcnt: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__hcnt);			// 0x30 / hpos when read?
		ImGui::Text("        vcnt: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__vcnt);			// 0x34 / vpos when read?
		ImGui::Text("        seed: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__seed);			// 0x38
		ImGui::Text("      random: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__random);			// 0x3c - read only?
		ImGui::Separator();
		ImGui::Text("   irq0_pend: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq0_pend);		// 0x40/0x44.
		ImGui::Text(" irq0_enable: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq0_enable);    // 0x48/0x4c.
		ImGui::Text("   irq0_trig: %d", top->rootp->core_3do__DOT__clio_inst__DOT__irq0_trig);
		ImGui::Text("        mode: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__mode);			// 0x50/0x54.
		ImGui::Text("     badbits: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__badbits);		// 0x58 - for reading things like DMA fail reasons?
		ImGui::Text("       spare: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__spare);			// 0x5c - ?
		ImGui::Text("   irq1_pend: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq1_pend);		// 0x60/0x64.
		ImGui::Text(" irq1_enable: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq1_enable);    // 0x68/0x6c.
		ImGui::Text("   irq1_trig: %d", top->rootp->core_3do__DOT__clio_inst__DOT__irq1_trig);
		ImGui::Separator();
		ImGui::Text("      hdelay: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__hdelay);			// 0x80
		ImGui::Text("   adbio_reg: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg);		// 0x84
		ImGui::Text("      adbctl: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__adbctl);			// 0x88
		ImGui::Separator();
		ImGui::Text("       slack: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__slack);			// 0x220
		ImGui::Text("     dmactrl: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dmactrl);		// 0x304 set / 0x308 clear.
		ImGui::Text("      expctl: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__expctl);			// 0x400 set / 0x404 clear.
		ImGui::Text("     type0_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__type0_4);		// 0x408
		ImGui::Text("      dipir1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dipir1);			// 0x410
		ImGui::Text("      dipir2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dipir2);			// 0x414
		ImGui::Separator();
		ImGui::Text("    unclerev: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__unclerev);		// 0xc000
		ImGui::Text("unc_soft_rev: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__unc_soft_rev);	// 0xc004
		ImGui::Text("  uncle_addr: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__uncle_addr);		// 0xc008
		ImGui::Text("   uncle_rom: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__uncle_rom);		// 0xc00c
		ImGui::Separator();
		ImGui::Text("Opera sound_out: 0x%08X", sound_out);
		ImGui::End();

		ImGui::Begin("CLIO Timers");
		ImGui::Text("  cnt_0: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr0_inst__DOT__tmr_cnt);	// 0x100
		ImGui::SameLine(); ImGui::Text("  bkp_0: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr0_inst__DOT__tmr_bkp);	// 0x104
		ImGui::Text("  cnt_1: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr1_inst__DOT__tmr_cnt);	// 0x108
		ImGui::SameLine(); ImGui::Text("  bkp_1: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr1_inst__DOT__tmr_bkp);	// 0x10c
		ImGui::Text("  cnt_2: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr2_inst__DOT__tmr_cnt);	// 0x110
		ImGui::SameLine(); ImGui::Text("  bkp_2: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr2_inst__DOT__tmr_bkp);	// 0x114
		ImGui::Text("  cnt_3: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr3_inst__DOT__tmr_cnt);	// 0x118
		ImGui::SameLine(); ImGui::Text("  bkp_3: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr3_inst__DOT__tmr_bkp);	// 0x11c
		ImGui::Text("  cnt_4: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr4_inst__DOT__tmr_cnt);	// 0x120
		ImGui::SameLine(); ImGui::Text("  bkp_4: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr4_inst__DOT__tmr_bkp);	// 0x124
		ImGui::Text("  cnt_5: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr5_inst__DOT__tmr_cnt);	// 0x128
		ImGui::SameLine(); ImGui::Text("  bkp_5: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr5_inst__DOT__tmr_bkp);	// 0x12c
		ImGui::Text("  cnt_6: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr6_inst__DOT__tmr_cnt);	// 0x130
		ImGui::SameLine(); ImGui::Text("  bkp_6: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr6_inst__DOT__tmr_bkp);	// 0x134
		ImGui::Text("  cnt_7: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr7_inst__DOT__tmr_cnt);	// 0x138
		ImGui::SameLine(); ImGui::Text("  bkp_7: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr7_inst__DOT__tmr_bkp);	// 0x13c
		ImGui::Text("  cnt_8: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr8_inst__DOT__tmr_cnt);	// 0x140
		ImGui::SameLine(); ImGui::Text("  bkp_8: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr8_inst__DOT__tmr_bkp);	// 0x144
		ImGui::Text("  cnt_9: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr9_inst__DOT__tmr_cnt);	// 0x148
		ImGui::SameLine(); ImGui::Text("  bkp_9: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr9_inst__DOT__tmr_bkp);	// 0x14c
		ImGui::Text(" cnt_10: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr10_inst__DOT__tmr_cnt);	// 0x150
		ImGui::SameLine(); ImGui::Text(" bkp_10: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr10_inst__DOT__tmr_bkp);	// 0x154
		ImGui::Text(" cnt_11: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr11_inst__DOT__tmr_cnt);	// 0x158
		ImGui::SameLine(); ImGui::Text(" bkp_11: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr11_inst__DOT__tmr_bkp);	// 0x15c
		ImGui::Text(" cnt_12: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr12_inst__DOT__tmr_cnt);	// 0x160
		ImGui::SameLine(); ImGui::Text(" bkp_12: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr12_inst__DOT__tmr_bkp);	// 0x164
		ImGui::Text(" cnt_13: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr13_inst__DOT__tmr_cnt);	// 0x168
		ImGui::SameLine(); ImGui::Text(" bkp_13: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr13_inst__DOT__tmr_bkp);	// 0x16c
		ImGui::Text(" cnt_14: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr14_inst__DOT__tmr_cnt);	// 0x170
		ImGui::SameLine(); ImGui::Text(" bkp_14: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr14_inst__DOT__tmr_bkp);	// 0x174
		ImGui::Text(" cnt_15: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr15_inst__DOT__tmr_cnt);	// 0x178
		ImGui::SameLine(); ImGui::Text(" bkp_15: 0x%04X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr15_inst__DOT__tmr_bkp);	// 0x17c
		ImGui::Separator();
		ImGui::Text("  tmr_ctrl_l: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr_ctrl_l);		// TODO !!
		ImGui::Text("  tmr_ctrl_u: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__tmr_ctrl_u);		// Not 100% sure how this should read back!!
		ImGui::End();

		ImGui::Begin("CLIO Xbus regs");
		ImGui::Text(" sel_0: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_0);                // 0x500
		ImGui::SameLine(); ImGui::Text(" poll_0: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_0);              // 0x540
		ImGui::Text(" sel_1: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_1);                // 0x504
		ImGui::SameLine(); ImGui::Text(" poll_1: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_1);              // 0x544
		ImGui::Text(" sel_2: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_2);                // 0x508
		ImGui::SameLine(); ImGui::Text(" poll_2: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_2);              // 0x548
		ImGui::Text(" sel_3: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_3);                // 0x50c
		ImGui::SameLine(); ImGui::Text(" poll_3: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_3);              // 0x54c
		ImGui::Text(" sel_4: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_4);                // 0x510
		ImGui::SameLine(); ImGui::Text(" poll_4: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_4);              // 0x550
		ImGui::Text(" sel_5: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_5);                // 0x514
		ImGui::SameLine(); ImGui::Text(" poll_5: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_5);              // 0x554
		ImGui::Text(" sel_6: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_6);                // 0x518
		ImGui::SameLine(); ImGui::Text(" poll_6: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_6);              // 0x558
		ImGui::Text(" sel_7: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_7);                // 0x51c
		ImGui::SameLine(); ImGui::Text(" poll_7: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_7);              // 0x55c
		ImGui::Text(" sel_8: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_8);                // 0x520
		ImGui::SameLine(); ImGui::Text(" poll_8: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_8);              // 0x560
		ImGui::Text(" sel_9: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_9);                // 0x524
		ImGui::SameLine(); ImGui::Text(" poll_9: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_9);              // 0x564
		ImGui::Text("sel_10: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_10);               // 0x528
		ImGui::SameLine(); ImGui::Text("poll_10: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_10);             // 0x568
		ImGui::Text("sel_11: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_11);               // 0x52c
		ImGui::SameLine(); ImGui::Text("poll_11: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_11);             // 0x56c
		ImGui::Text("sel_12: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_12);               // 0x530
		ImGui::SameLine(); ImGui::Text("poll_12: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_12);             // 0x570
		ImGui::Text("sel_13: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_13);               // 0x534
		ImGui::SameLine(); ImGui::Text("poll_13: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_13);             // 0x574
		ImGui::Text("sel_14: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_14);               // 0x538
		ImGui::SameLine(); ImGui::Text("poll_14: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_14);             // 0x578
		ImGui::Text("sel_15: 0x%02X ", top->rootp->core_3do__DOT__clio_inst__DOT__sel_15);               // 0x53c
		ImGui::SameLine(); ImGui::Text("poll_15: 0x%02X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_15);             // 0x57c
		ImGui::Separator();
		ImGui::Text(" CD LBA: 0x%08X  ", CDIMAGE_SECTOR);
		ImGui::Text(" CD Off: 0x%08X  ", CDIMAGE_SECTOR*CDIMAGE_SECTOR_SIZE);
		ImGui::End();

		ImGui::Begin("CLIO DSP regs");
		ImGui::Text("     sema: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sema);		// 0x17d0
		ImGui::Text("  semaack: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__semaack);	// 0x17d4
		ImGui::Separator();
		ImGui::Text("   dspdma: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspdma);	// 0x17e0
		ImGui::Text(" dspprst0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspprst0);	// 0x17e4
		ImGui::Text(" dspprst1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspprst1);	// 0x17e8
		ImGui::Text("   dspppc: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspppc);    // 0x17f4
		ImGui::Text("   dsppnr: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dsppnr);	// 0x17f8
		ImGui::Text("   dsppgw: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dsppgw);	// 0x17fc
		ImGui::Separator();
		ImGui::Text("dsppclkreload: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dsppclkreload);// 0x39dc ?
		ImGui::End();

		ImGui::Begin("MADAM Registers");
		ImGui::Text("     mctl: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__mctl);
		ImGui::Text("   sltime: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__sltime);
		ImGui::Separator();
		ImGui::Text(" vdl_addr: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma24_curaddr);	// 0x580
		ImGui::Separator();
		ImGui::Text(" VDL still in C...");
		ImGui::Text("  vdl_ctl: 0x%08X", vdl_ctl);
		ImGui::Text(" vdl_curr: 0x%08X", vdl_curr);
		ImGui::Text(" vdl_prev: 0x%08X", vdl_prev);
		ImGui::Text(" vdl_next: 0x%08X", vdl_next);
		ImGui::End();

		ImGui::Begin("CEL Registers");
		//ImGui::Text(" currentccb: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma26_curaddr);
		ImGui::Text(" currentccb: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__currentccb);
		//ImGui::Text("    nextccb: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma26_curlen);
		ImGui::Text("    nextccb: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__nextccb);
		ImGui::Text("   plutdata: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma26_nextaddr);
		ImGui::Text("      pdata: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma26_nextlen);
		ImGui::Text("  engafetch: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma27_curaddr);
		ImGui::Text("    engalen: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma27_curlen);
		ImGui::Text("  engbfetch: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma27_nextaddr);
		ImGui::Text("    engblen: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_stack_inst__DOT__dma27_nextlen);
		ImGui::Separator();
		ImGui::Text("      state: %d", top->rootp->core_3do__DOT__madam_inst__DOT__state);
		ImGui::Text("   dma_addr: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__dma_addr);
		ImGui::Text("      flags: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__flags);
		ImGui::Text("    nextptr: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__nextptr);
		ImGui::Text("  sourceptr: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__sourceptr);
		ImGui::Text("    plutptr: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__plutptr);

		int32_t xpos = top->rootp->core_3do__DOT__madam_inst__DOT__xpos;	// 16.16
		int32_t ypos = top->rootp->core_3do__DOT__madam_inst__DOT__ypos;	// 16.16
		int32_t hdx = top->rootp->core_3do__DOT__madam_inst__DOT__hdx;		// 12.20
		int32_t hdy = top->rootp->core_3do__DOT__madam_inst__DOT__hdy;		// 12.20
		int32_t vdx = top->rootp->core_3do__DOT__madam_inst__DOT__vdx;		// 16.16
		int32_t vdy = top->rootp->core_3do__DOT__madam_inst__DOT__vdy;		// 16.16
		int32_t hddx = top->rootp->core_3do__DOT__madam_inst__DOT__hddx;	// 12.20
		int32_t hddy = top->rootp->core_3do__DOT__madam_inst__DOT__hddy;	// 12.20

		if (top->rootp->core_3do__DOT__madam_inst__DOT__nextccb>0) {
			for (int xp = 0; xp < 16; xp++) {
				uint32_t x = xpos>>16;
				uint32_t y = ypos>>16;
				for (int yp = 0; yp < 16; yp++) {
					disp_ptr[ ((y+yp)*320)+x+xp & 0xfffff ] = 0xff00ff00;	// ABGR.
				}
			}
		}

		ImGui::Text("       xpos: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__xpos);
		ImGui::SameLine(); ImGui::Text(" %f", (double)xpos / (double)(1<<16));

		ImGui::Text("       ypos: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__ypos);
		ImGui::SameLine(); ImGui::Text(" %f", (double)ypos / (double)(1<<16));

		ImGui::Text("        hdx: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__hdx);
		ImGui::SameLine(); ImGui::Text(" %lf", (double)hdx / (double)(1<<20));
		
		ImGui::Text("        hdy: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__hdy);
		ImGui::SameLine(); ImGui::Text(" %lf", (double)hdy / (double)(1<<20));

		ImGui::Text("        vdx: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__vdx);
		ImGui::SameLine(); ImGui::Text(" %lf", (double)vdx / (double)(1<<16));

		ImGui::Text("        vdy: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__vdy);
		ImGui::SameLine(); ImGui::Text(" %lf", (double)vdy / (double)(1<<16));

		ImGui::Text("       hddx: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__hddx);
		ImGui::SameLine(); ImGui::Text(" %lf", (double)hddx / (double)(1<<20));

		ImGui::Text("       hddy: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__hddy);
		ImGui::SameLine(); ImGui::Text(" %lf", (double)hddy / (double)(1<<20));

		ImGui::Text("       pixc: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__pixc);
		ImGui::Text("       pre0: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__pre0);
		ImGui::Text("       pre1: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__pre1);
		ImGui::End();

		uint16_t store_u = top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__store_u;
		uint32_t store_l = top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__store_l;
		uint8_t pack_type = top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__pack_type;
		uint8_t bpp = top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__bpp;

		ImGui::Begin("CEL Unpacker");
		ImGui::Text("      state: %d", top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__state);
		
		ImGui::Text("       bpp: %d", bpp);
		ImGui::SameLine();
		if (bpp == 1) ImGui::Text(" (1BPP) ");
		else if (bpp == 2) ImGui::Text(" (2BPP) ");
		else if (bpp == 3) ImGui::Text(" (4BPP) ");
		else if (bpp == 4) ImGui::Text(" (6BPP) ");
		else if (bpp == 5) ImGui::Text(" (8BPP) ");
		else if (bpp == 6) ImGui::Text(" (16BPP) ");
		else ImGui::Text(" ??? "); // bpp==0 and bpp==7 are reserved.

		ImGui::Text("     offset: %d", top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__offset);
		
		ImGui::Text("       type: %d", pack_type);
		ImGui::SameLine();
		if (pack_type==0) ImGui::Text(" EOL ");
		else if (pack_type==1) ImGui::Text(" LITERAL ");
		else if (pack_type==2) ImGui::Text(" TRANSP ");
		else if (pack_type==3) ImGui::Text(" REPEAT ");
		else ImGui::Text(" ??? ");

		ImGui::Text("      count: %d", top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__count);
		ImGui::Text("      shift: %d", top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__shift);
		ImGui::Text("     rd_req: %d", top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__rd_req);
		ImGui::Text("      store: 0x%04X %08X", store_u, store_l);
		ImGui::Text("    col_out: 0x%04X", top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__col_out);
		ImGui::Text("        eol: %d", top->rootp->core_3do__DOT__madam_inst__DOT__unpacker_inst__DOT__eol);
		ImGui::End();

		/*
		ImGui::Begin("Sim XBUS stuff");
		ImGui::Text("  xdev[0]: 0x%02X", xdev[0]);
		ImGui::Text("  xdev[1]: 0x%02X", xdev[1]);
		ImGui::Text("  xdev[2]: 0x%02X", xdev[2]);
		ImGui::Text("  xdev[3]: 0x%02X", xdev[3]);
		ImGui::Text("  xdev[4]: 0x%02X", xdev[4]);
		ImGui::Text("  xdev[5]: 0x%02X", xdev[5]);
		ImGui::Text("  xdev[6]: 0x%02X", xdev[6]);
		ImGui::Text("  xdev[7]: 0x%02X", xdev[7]);
		ImGui::Text("  xdev[8]: 0x%02X", xdev[8]);
		ImGui::Text("  xdev[9]: 0x%02X", xdev[9]);
		ImGui::Text(" xdev[10]: 0x%02X", xdev[10]);
		ImGui::Text(" xdev[11]: 0x%02X", xdev[11]);
		ImGui::Text(" xdev[12]: 0x%02X", xdev[12]);
		ImGui::Text(" xdev[13]: 0x%02X", xdev[13]);
		ImGui::Text(" xdev[14]: 0x%02X", xdev[14]);
		ImGui::Text(" xdev[15]: 0x%02X", xdev[15]);
		ImGui::Text("  XBUS.xb_sel_l: 0x%02X", XBUS.xb_sel_l);
		ImGui::Text("  XBUS.xb_sel_h: 0x%02X", XBUS.xb_sel_h);
		ImGui::Text("      XBUS.polf: 0x%02X", XBUS.polf);
		ImGui::Text("   XBUS.poldevf: 0x%02X", XBUS.poldevf);
		ImGui::Text("      stdevf[0]: 0x%02X", XBUS.stdevf[0]);
		ImGui::Text("      stdevf[1]: 0x%02X", XBUS.stdevf[1]);
		ImGui::Text("      stdevf[2]: 0x%02X", XBUS.stdevf[2]);
		ImGui::Text("      stdevf[3]: 0x%02X", XBUS.stdevf[3]);
		ImGui::Text("      stdevf[4]: 0x%02X", XBUS.stdevf[4]);
		ImGui::Text("      stdevf[5]: 0x%02X", XBUS.stdevf[5]);
		ImGui::Text("      stdevf[6]: 0x%02X", XBUS.stdevf[6]);
		ImGui::Text("      stdevf[7]: 0x%02X", XBUS.stdevf[7]);
		ImGui::Text("      stdevf[8]: 0x%02X", XBUS.stdevf[8]);
		ImGui::Text("      stdevf[9]: 0x%02X", XBUS.stdevf[9]);
		ImGui::Text("     stdevf[10]: 0x%02X", XBUS.stdevf[10]);
		ImGui::Text("     stdevf[11]: 0x%02X", XBUS.stdevf[11]);
		ImGui::Text("     stdevf[12]: 0x%02X", XBUS.stdevf[12]);
		ImGui::Text("     stdevf[13]: 0x%02X", XBUS.stdevf[13]);
		ImGui::Text("     stdevf[14]: 0x%02X", XBUS.stdevf[14]);
		ImGui::Text("     stdevf[15]: 0x%02X", XBUS.stdevf[15]);
		ImGui::Text("    XBUS.stlenf: 0x%02X", XBUS.stlenf);
		ImGui::Text("        cmdf[0]: 0x%02X", XBUS.cmdf[0]);
		ImGui::Text("        cmdf[1]: 0x%02X", XBUS.cmdf[1]);
		ImGui::Text("        cmdf[2]: 0x%02X", XBUS.cmdf[2]);
		ImGui::Text("        cmdf[3]: 0x%02X", XBUS.cmdf[3]);
		ImGui::Text("        cmdf[4]: 0x%02X", XBUS.cmdf[4]);
		ImGui::Text("        cmdf[5]: 0x%02X", XBUS.cmdf[5]);
		ImGui::Text("        cmdf[6]: 0x%02X", XBUS.cmdf[6]);
		ImGui::Text("        cmdf[7]: 0x%02X", XBUS.cmdf[7]);
		ImGui::Text("        cmdf[8]: 0x%02X", XBUS.cmdf[8]);
		ImGui::Text("   XBUS.cmdptrf: 0x%02X", XBUS.cmdptrf);
		ImGui::Separator();
		ImGui::End();
		*/

		/*
		ImGui::Begin("Matrix Engine");
		ImGui::Text("   MI00: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI00);
		ImGui::Text("   MI01: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI01);
		ImGui::Text("   MI02: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI02);
		ImGui::Text("   MI03: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI03);
		ImGui::Text("   MI10: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI10);
		ImGui::Text("   MI11: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI11);
		ImGui::Text("   MI12: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI12);
		ImGui::Text("   MI13: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI13);
		ImGui::Text("   MI20: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI20);
		ImGui::Text("   MI21: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI21);
		ImGui::Text("   MI22: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI22);
		ImGui::Text("   MI23: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI23);
		ImGui::Text("   MI30: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI30);
		ImGui::Text("   MI31: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI31);
		ImGui::Text("   MI32: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI32);
		ImGui::Text("   MI33: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MI33);
		ImGui::Separator();
		ImGui::Text("    MV0: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MV0);
		ImGui::Text("    MV1: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MV1);
		ImGui::Text("    MV2: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MV2);
		ImGui::Text("    MV3: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__MV3);
		ImGui::Separator();
		ImGui::Text(" tmpMO0: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO0);
		ImGui::Text(" tmpMO1: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO1);
		ImGui::Text(" tmpMO2: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO2);
		ImGui::Text(" tmpMO3: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO3);
		ImGui::Separator();
		ImGui::Text("Nfrac16: 0x%016llX", top->rootp->core_3do__DOT__matrix_inst__DOT__Nfrac16);
		ImGui::Separator();
		ImGui::Text("    MO0: 0x%08X", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO3);
		ImGui::Text("    MO1: 0x%08X", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO3);
		ImGui::Text("    MO2: 0x%08X", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO3);
		ImGui::Text("    MO3: 0x%08X", top->rootp->core_3do__DOT__matrix_inst__DOT__tmpMO3);
		ImGui::End();
		*/

		// Update the texture for disp_ptr!
		// D3D11_USAGE_DEFAULT MUST be set in the texture description (somewhere above) for this to work.
		// (D3D11_USAGE_DYNAMIC is for use with map / unmap.) ElectronAsh.
		g_pd3dDeviceContext->UpdateSubresource(pTexture, 0, NULL, disp_ptr, width * 4, 0);

		g_pd3dDeviceContext->UpdateSubresource(pTexture2, 0, NULL, disp2_ptr, width * 4, 0);
		//g_pd3dDeviceContext->UpdateSubresource(pTexture2, 0, NULL, g_VIDEO_BUFFER, width * 4, 0);

		// Rendering
		ImGui::Render();
		g_pd3dDeviceContext->OMSetRenderTargets(1, &g_mainRenderTargetView, NULL);
		g_pd3dDeviceContext->ClearRenderTargetView(g_mainRenderTargetView, (float*)&clear_color);
		ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

		//g_pSwapChain->Present(1, 0); // Present with vsync
		g_pSwapChain->Present(0, 0); // Present without vsync
	}
	// Close imgui stuff properly...
	ImGui_ImplDX11_Shutdown();
	ImGui_ImplWin32_Shutdown();
	ImGui::DestroyContext();

	CleanupDeviceD3D();
	DestroyWindow(hwnd);
	UnregisterClass(wc.lpszClassName, wc.hInstance);

	return 0;
}
