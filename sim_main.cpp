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

FILE *logfile;


#include <d3d11.h>
#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include <tchar.h>

// DirectX data
static ID3D11Device*            g_pd3dDevice = NULL;
static ID3D11DeviceContext*     g_pd3dDeviceContext = NULL;
static IDXGIFactory*            g_pFactory = NULL;
static ID3D11Buffer*            g_pVB = NULL;
static ID3D11Buffer*            g_pIB = NULL;
static ID3D10Blob*              g_pVertexShaderBlob = NULL;
static ID3D11VertexShader*      g_pVertexShader = NULL;
static ID3D11InputLayout*       g_pInputLayout = NULL;
static ID3D11Buffer*            g_pVertexConstantBuffer = NULL;
static ID3D10Blob*              g_pPixelShaderBlob = NULL;
static ID3D11PixelShader*       g_pPixelShader = NULL;
static ID3D11SamplerState*      g_pFontSampler = NULL;
static ID3D11ShaderResourceView*g_pFontTextureView = NULL;
static ID3D11RasterizerState*   g_pRasterizerState = NULL;
static ID3D11BlendState*        g_pBlendState = NULL;
static ID3D11DepthStencilState* g_pDepthStencilState = NULL;
static int                      g_VertexBufferSize = 5000, g_IndexBufferSize = 10000;


// Instantiation of module.
Vcore_3do* top = new Vcore_3do;

bool next_ack = 0;
bool do_printf = 0;

bool rom_select = 0;	// Select the BIOS ROM at startup! (not Kanji).

bool map_bios = 1;
uint32_t rom_byteswapped;
uint32_t rom2_byteswapped;
uint32_t ram_byteswapped;

uint16_t shift_reg = 0;
bool toggle = 1;

uint32_t irq0 = 0x00000000;
uint32_t irq1 = 0x00000000;

uint32_t mask0 = 0x00000000;
uint32_t mask1 = 0x00000000;

//uint32_t mctl_reg = 0x0001E000;
uint32_t mctl_reg = 0x00000000;

//uint32_t msys_reg = 0x00000029;
//uint32_t msys_reg = 0x00000051;
uint32_t msys_reg = 0x00000000;
//uint32_t vdl_addr_reg = 0x0000000;

//uint32_t sltime_reg = 0x00178906;
uint32_t sltime_reg = 0x00000000;

uint32_t cstat_reg = 0x00000001;	// POR bit (0) set! fixel said this is what the starting value should be.
//uint32_t cstat_reg = 0x00000040;	// DIPIR (Disc Inserted Provide Interrupt Response) bit (6) set! Opera does this, but fixel suggests Opera has other patches to make this work!

char my_string[1024];

bool trace = 0;

int pix_count = 0;

uint32_t clio_vcnt = 0;
//int vcnt_max = 262;
bool field = 1;
uint32_t vint0_reg;
uint32_t vint1_reg;

uint32_t cur_pc;
uint32_t old_pc;

bool madam_cs;
bool clio_cs;
bool svf_cs;
bool svf2_cs;

bool dump_ram = 0;

unsigned char rgb[3];
bool prev_vsync = 0;
int frame_count = 0;

bool prev_hsync = 0;
int line_count = 0;

bool run_enable = 0;
bool single_step = 0;
bool multi_step = 0;
int multi_step_amount = 8;

FILE *vgap;

// Data
static IDXGISwapChain*          g_pSwapChain = NULL;
static ID3D11RenderTargetView*  g_mainRenderTargetView = NULL;

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


vluint64_t main_time = 0;	// Current simulation time.

unsigned int file_size;

unsigned char buffer[16];

unsigned int rom_size = 1024 * 1024;		// 1MB. (8-bit wide array, 32-bit on the core).
uint8_t *rom_ptr = (uint8_t *) malloc(rom_size);

unsigned int rom2_size = 1024 * 1024;		// 1MB. (8-bit wide array, 32-bit on the core).
uint8_t *rom2_ptr = (uint8_t *) malloc(rom2_size);

unsigned int ram_size = 1024 * 2048;		// 2MB. (8-bit wide array, 32-bit on the core).
uint8_t *ram_ptr = (uint8_t *) malloc(ram_size);

unsigned int vram_size = 1024 * 256 * 4;	// 1MB. (32-bit wide).
uint32_t *vram_ptr = (uint32_t *)malloc(vram_size);

unsigned int nvram_size = 1024 * 128;		// 128KB?
uint32_t *nvram_ptr = (uint32_t *) malloc(nvram_size);

unsigned int disp_size = 1024 * 1024 * 4;	// 4MB. (32-bit wide). Sim display window.
uint32_t *disp_ptr = (uint32_t *)malloc(disp_size);


double sc_time_stamp () {	// Called by $time in Verilog.
	return main_time;
}


uint32_t vdl_ctl;
uint32_t vdl_curr;
uint32_t vdl_prev;
uint32_t vdl_next;

uint32_t clut [32];

void process_vdl() {
	/*
	clut[0x00] = 0x000000; clut[0x01] = 0x080808; clut[0x02] = 0x101010; clut[0x03] = 0x191919; clut[0x04] = 0x212121; clut[0x05] = 0x292929; clut[0x06] = 0x313131; clut[0x07] = 0x3A3A3A;
	clut[0x08] = 0x424242; clut[0x09] = 0x4A4A4A; clut[0x0A] = 0x525252; clut[0x0B] = 0x5A5A5A; clut[0x0C] = 0x636363; clut[0x0D] = 0x6B6B6B; clut[0x0E] = 0x737373; clut[0x0F] = 0x7B7B7B;
	clut[0x10] = 0x848484; clut[0x11] = 0x8C8C8C; clut[0x12] = 0x949494; clut[0x13] = 0x9C9C9C; clut[0x14] = 0xA5A5A5; clut[0x15] = 0xADADAD; clut[0x16] = 0xB5B5B5; clut[0x17] = 0xBDBDBD;
	clut[0x18] = 0xC5C5C5; clut[0x19] = 0xCECECE; clut[0x1A] = 0xD6D6D6; clut[0x1B] = 0xDEDEDE; clut[0x1C] = 0xE6E6E6; clut[0x1D] = 0xEFEFEF; clut[0x1E] = 0xF8F8F8; clut[0x1F] = 0xFFFFFF;
	*/

	uint32_t offset = top->rootp->core_3do__DOT__madam_inst__DOT__vdl_addr & 0xFFFFF;

	// Read the VDL / CLUT from vram_ptr...
	if (offset>0) {
		for (int i=0; i<=35; i++) {
			if (i==0) vdl_ctl = vram_ptr[ (offset>>2)+i ];
			else if (i==1) vdl_curr = vram_ptr[ (offset>>2)+i ];
			else if (i==2) vdl_prev = vram_ptr[ (offset>>2)+i ];
			else if (i==3) vdl_next = vram_ptr[ (offset>>2)+i ];
			else if (i>=4) clut[i-4] = vram_ptr[ (offset>>2)+i ];
		}
	}

	// Copy the VRAM pixels into disp_ptr...
	// Just a dumb test atm. Assuming 16bpp from vram_ptr, with odd and even pixels in the upper/lower 16 bits.
	//
	// vram_ptr is 32-bit wide!
	// vram_size = 1MB, so needs to be divided by 4 if used as an index.
	//
	offset = 0xC0000;

	uint32_t my_line = 0;
	for (uint32_t i=0; i<(vram_size/16); i++) {
		uint16_t pixel;

		if ( (i%320)==0 ) my_line++;

		pixel = vram_ptr[ (offset>>2)+i ] >> 16;
		rgb[0] = clut[ (pixel & 0x7C00)>>10 ] >> 16;
		rgb[1] = clut[ (pixel & 0x03E0)>>5 ] >> 8;
		rgb[2] = clut[ (pixel & 0x001F)<<0 ] >> 0;
		disp_ptr[ i+(my_line*320) ] = 0xff<<24 | rgb[2]<<16 | rgb[1]<<8 | rgb[0];		// Our debugger framebuffer is in the 32-bit ABGR format.

		pixel = vram_ptr[ (offset>>2)+i ] & 0xFFFF;
		rgb[0] = clut[ (pixel & 0x7C00)>>10 ] >> 16;
		rgb[1] = clut[ (pixel & 0x03E0)>>5 ] >> 8;
		rgb[2] = clut[ (pixel & 0x001F)<<0 ] >> 0;
		disp_ptr[ i+(my_line*320)+320 ] = 0xff<<24 | rgb[2]<<16 | rgb[1]<<8 | rgb[0];	// Our debugger framebuffer is in the 32-bit ABGR format.
	}
}

void print_to_log(uint32_t addr_, uint32_t val_, uint8_t write, uint32_t cur_pc) {
	
	if (addr_>=0x03100000 && addr_<=0x0313FFFF) fprintf(logfile, "Brooktree       ");
	//else if (addr_>=0x03140000 && addr_<=0x0315FFFF) fprintf(logfile, "NVRAM           ");
	else if (addr_==0x03180000) fprintf(logfile, "DiagPort        ");
	else if (addr_>=0x03180004 && addr_<=0x031BFFFF) fprintf(logfile, "Slow Bus        ");
	else if (addr_>=0x03200000 && addr_<=0x0320FFFF) fprintf(logfile, "VRAM SVF        ");
	else if (addr_>=0x032F0000 && addr_<=0x032FFFFF) fprintf(logfile, "Unknown         ");

	// MADAM...
	if (addr_>=0x03300000 && addr_<=0x033FFFFF) {
		switch (addr_) {
			case 0x03300000: if (write) { fprintf(logfile, "MADAM Print  "); break; }
								   else { fprintf(logfile, "MADAM Revision  "); break; }
			case 0x03300004: { fprintf(logfile, "MADAM msysbits  "); break; }
			case 0x03300008: { fprintf(logfile, "MADAM mctl      "); break; }
			case 0x0330000C: { fprintf(logfile, "MADAM sltime    "); break; }
			case 0x03300580: { fprintf(logfile, "MADAM vdl_addr! "); break; }
			default: { fprintf(logfile, "MADAM ??        "); break; }
		}
	}

	// CLIO...
	if (addr_ >= 0x03400000 && addr_ <= 0x034FFFFF) {
		switch (addr_) {
			case 0x03400000: { fprintf(logfile, "CLIO Revision   "); break; }
			case 0x03400004: { fprintf(logfile, "CLIO csysbits   "); break; }

			case 0x03400008: { fprintf(logfile, "CLIO vint0      "); break; }
			case 0x0340000C: { fprintf(logfile, "CLIO vint1      "); break; }

			case 0x03400010: { fprintf(logfile, "CLIO DigVidEnc  "); break; }
			case 0x03400014: { fprintf(logfile, "CLIO SbusState  "); break; }

			case 0x03400020: { fprintf(logfile, "CLIO audin      "); break; }
			case 0x03400024: { fprintf(logfile, "CLIO audout     "); break; }

			case 0x03400028: { fprintf(logfile, "CLIO cstatbits  "); break; }
			case 0x0340002c: { fprintf(logfile, "CLIO WatchDog   "); break; }

			case 0x03400030: { fprintf(logfile, "CLIO hcnt       "); break; }
			case 0x03400034: { fprintf(logfile, "CLIO vcnt       "); break; }

			case 0x03400038: { fprintf(logfile, "CLIO RandSeed   "); break; }
			case 0x0340003c: { fprintf(logfile, "CLIO RandSample "); break; }

			case 0x03400040: { fprintf(logfile, "CLIO irq0 set   "); break; }
			case 0x03400044: { fprintf(logfile, "CLIO irq0 clear "); break; }
			case 0x03400048: { fprintf(logfile, "CLIO mask0 set  "); break; }
			case 0x0340004c: { fprintf(logfile, "CLIO mask0 clear"); break; }

			case 0x03400050: { fprintf(logfile, "CLIO SetMode    "); break; }
			case 0x03400054: { fprintf(logfile, "CLIO ClrMode    "); break; }

			case 0x03400058: { fprintf(logfile, "CLIO BadBits    "); break; }
			case 0x0340005c: { fprintf(logfile, "CLIO Spare      "); break; }

			case 0x03400060: { fprintf(logfile, "CLIO irq1 set   "); break; }
			case 0x03400064: { fprintf(logfile, "CLIO irq1 clear "); break; }
			case 0x03400068: { fprintf(logfile, "CLIO mask1 set  "); break; }
			case 0x0340006c: { fprintf(logfile, "CLIO mask1 clear"); break; }

			case 0x03400080: { fprintf(logfile, "CLIO hdelay     "); break; }
			case 0x03400084: { fprintf(logfile, "CLIO adbio      "); break; }
			case 0x03400088: { fprintf(logfile, "CLIO adbctl     "); break; }

			case 0x03400100: { fprintf(logfile, "CLIO tmr0_cnt   "); break; }
			case 0x03400108: { fprintf(logfile, "CLIO tmr1_cnt   "); break; }
			case 0x03400110: { fprintf(logfile, "CLIO tmr2_cnt   "); break; }
			case 0x03400118: { fprintf(logfile, "CLIO tmr3_cnt   "); break; }
			case 0x03400120: { fprintf(logfile, "CLIO tmr4_cnt   "); break; }
			case 0x03400128: { fprintf(logfile, "CLIO tmr5_cnt   "); break; }
			case 0x03400130: { fprintf(logfile, "CLIO tmr6_cnt   "); break; }
			case 0x03400138: { fprintf(logfile, "CLIO tmr7_cnt   "); break; }
			case 0x03400140: { fprintf(logfile, "CLIO tmr8_cnt   "); break; }
			case 0x03400148: { fprintf(logfile, "CLIO tmr9_cnt   "); break; }
			case 0x03400150: { fprintf(logfile, "CLIO tmr10_cnt  "); break; }
			case 0x03400158: { fprintf(logfile, "CLIO tmr11_cnt  "); break; }
			case 0x03400160: { fprintf(logfile, "CLIO tmr12_cnt  "); break; }
			case 0x03400168: { fprintf(logfile, "CLIO tmr13_cnt  "); break; }
			case 0x03400170: { fprintf(logfile, "CLIO tmr14_cnt  "); break; }
			case 0x03400178: { fprintf(logfile, "CLIO tmr15_cnt  "); break; }

			case 0x03400104: { fprintf(logfile, "CLIO tmr0_bkp   "); break; }
			case 0x0340010c: { fprintf(logfile, "CLIO tmr1_bkp   "); break; }
			case 0x03400114: { fprintf(logfile, "CLIO tmr2_bkp   "); break; }
			case 0x0340011c: { fprintf(logfile, "CLIO tmr3_bkp   "); break; }
			case 0x03400124: { fprintf(logfile, "CLIO tmr4_bkp   "); break; }
			case 0x0340012c: { fprintf(logfile, "CLIO tmr5_bkp   "); break; }
			case 0x03400134: { fprintf(logfile, "CLIO tmr6_bkp   "); break; }
			case 0x0340013c: { fprintf(logfile, "CLIO tmr7_bkp   "); break; }
			case 0x03400144: { fprintf(logfile, "CLIO tmr8_bkp   "); break; }
			case 0x0340014c: { fprintf(logfile, "CLIO tmr9_bkp   "); break; }
			case 0x03400154: { fprintf(logfile, "CLIO tmr10_bkp  "); break; }
			case 0x0340015c: { fprintf(logfile, "CLIO tmr11_bkp  "); break; }
			case 0x03400164: { fprintf(logfile, "CLIO tmr12_bkp  "); break; }
			case 0x0340016c: { fprintf(logfile, "CLIO tmr13_bkp  "); break; }
			case 0x03400174: { fprintf(logfile, "CLIO tmr14_bkp  "); break; }
			case 0x0340017c: { fprintf(logfile, "CLIO tmr15_bkp  "); break; }

			case 0x03400200: { fprintf(logfile, "CLIO tmr1_set   "); break; }
			case 0x03400204: { fprintf(logfile, "CLIO tmr1_clr   "); break; }
			case 0x03400208: { fprintf(logfile, "CLIO tmr2_set   "); break; }
			case 0x0340020C: { fprintf(logfile, "CLIO tmr2_clr   "); break; }

			case 0x03400220: { fprintf(logfile, "CLIO TmrClack   "); break; }
			case 0x03400304: { fprintf(logfile, "CLIO SetDMAEna  "); break; }
			case 0x03400308: { fprintf(logfile, "CLIO ClrDMAEna  "); break; }

			case 0x03400380: { fprintf(logfile, "CLIO DMA DSPP0 "); break; }
			case 0x03400384: { fprintf(logfile, "CLIO DMA DSPP1 "); break; }
			case 0x03400388: { fprintf(logfile, "CLIO DMA DSPP2 "); break; }
			case 0x0340038c: { fprintf(logfile, "CLIO DMA DSPP3 "); break; }
			case 0x03400390: { fprintf(logfile, "CLIO DMA DSPP4 "); break; }
			case 0x03400394: { fprintf(logfile, "CLIO DMA DSPP5 "); break; }
			case 0x03400398: { fprintf(logfile, "CLIO DMA DSPP6 "); break; }
			case 0x0340039c: { fprintf(logfile, "CLIO DMA DSPP7 "); break; }
			case 0x034003a0: { fprintf(logfile, "CLIO DMA DSPP8 "); break; }
			case 0x034003a4: { fprintf(logfile, "CLIO DMA DSPP9 "); break; }
			case 0x034003a8: { fprintf(logfile, "CLIO DMA DSPP10"); break; }
			case 0x034003ac: { fprintf(logfile, "CLIO DMA DSPP11"); break; }
			case 0x034003b0: { fprintf(logfile, "CLIO DMA DSPP12"); break; }
			case 0x034003b4: { fprintf(logfile, "CLIO DMA DSPP13"); break; }
			case 0x034003b8: { fprintf(logfile, "CLIO DMA DSPP14"); break; }
			case 0x034003bc: { fprintf(logfile, "CLIO DMA DSPP15"); break; }

						   // Only the first FOUR FIFO Status DSPP-to-DMA regs are used in clio.h in the Portfolio/Opera (OS) source?
			case 0x034003c0: { fprintf(logfile, "CLIO DSPP DMA0 "); break; }
			case 0x034003c4: { fprintf(logfile, "CLIO DSPP DMA1 "); break; }
			case 0x034003c8: { fprintf(logfile, "CLIO DSPP DMA2 "); break; }
			case 0x034003cc: { fprintf(logfile, "CLIO DSPP DMA3 "); break; }
			case 0x034003d0: { fprintf(logfile, "CLIO DSPP DMA4 "); break; }
			case 0x034003d4: { fprintf(logfile, "CLIO DSPP DMA5 "); break; }
			case 0x034003d8: { fprintf(logfile, "CLIO DSPP DMA6 "); break; }
			case 0x034003dc: { fprintf(logfile, "CLIO DSPP DMA7 "); break; }
			case 0x034003e0: { fprintf(logfile, "CLIO DSPP DMA8 "); break; }
			case 0x034003e4: { fprintf(logfile, "CLIO DSPP DMA9 "); break; }
			case 0x034003e8: { fprintf(logfile, "CLIO DSPP DMA10"); break; }
			case 0x034003ec: { fprintf(logfile, "CLIO DSPP DMA11"); break; }
			case 0x034003f0: { fprintf(logfile, "CLIO DSPP DMA12"); break; }
			case 0x034003f4: { fprintf(logfile, "CLIO DSPP DMA13"); break; }
			case 0x034003f8: { fprintf(logfile, "CLIO DSPP DMA14"); break; }
			case 0x034003fc: { fprintf(logfile, "CLIO DSPP DMA15"); break; }

			case 0x03400400: { fprintf(logfile, "CLIO expctl_set "); break; }
			case 0x03400404: { fprintf(logfile, "CLIO expctl_clr "); break; }
			case 0x03400408: { fprintf(logfile, "CLIO type0_4    "); break; }
			case 0x03400410: { fprintf(logfile, "CLIO dipir1     "); break; }
			case 0x03400414: { fprintf(logfile, "CLIO dipir2     "); break; }

			case 0x03400500: { fprintf(logfile, "CLIO sel0       "); break; }
			case 0x03400504: { fprintf(logfile, "CLIO sel1       "); break; }
			case 0x03400508: { fprintf(logfile, "CLIO sel2       "); break; }
			case 0x0340050c: { fprintf(logfile, "CLIO sel3       "); break; }
			case 0x03400510: { fprintf(logfile, "CLIO sel4       "); break; }
			case 0x03400514: { fprintf(logfile, "CLIO sel5       "); break; }
			case 0x03400518: { fprintf(logfile, "CLIO sel6       "); break; }
			case 0x0340051c: { fprintf(logfile, "CLIO sel7       "); break; }
			case 0x03400520: { fprintf(logfile, "CLIO sel8       "); break; }
			case 0x03400524: { fprintf(logfile, "CLIO sel9       "); break; }
			case 0x03400528: { fprintf(logfile, "CLIO sel10      "); break; }
			case 0x0340052c: { fprintf(logfile, "CLIO sel11      "); break; }
			case 0x03400530: { fprintf(logfile, "CLIO sel12      "); break; }
			case 0x03400534: { fprintf(logfile, "CLIO sel13      "); break; }
			case 0x03400538: { fprintf(logfile, "CLIO sel14      "); break; }
			case 0x0340053c: { fprintf(logfile, "CLIO sel15      "); break; }

			case 0x03400540: { fprintf(logfile, "CLIO poll0      "); break; }
			case 0x03400544: { fprintf(logfile, "CLIO poll1      "); break; }
			case 0x03400548: { fprintf(logfile, "CLIO poll2      "); break; }
			case 0x0340054c: { fprintf(logfile, "CLIO poll3      "); break; }
			case 0x03400550: { fprintf(logfile, "CLIO poll4      "); break; }
			case 0x03400554: { fprintf(logfile, "CLIO poll5      "); break; }
			case 0x03400558: { fprintf(logfile, "CLIO poll6      "); break; }
			case 0x0340055c: { fprintf(logfile, "CLIO poll7      "); break; }
			case 0x03400560: { fprintf(logfile, "CLIO poll8      "); break; }
			case 0x03400564: { fprintf(logfile, "CLIO poll9      "); break; }
			case 0x03400568: { fprintf(logfile, "CLIO poll10     "); break; }
			case 0x0340056c: { fprintf(logfile, "CLIO poll11     "); break; }
			case 0x03400570: { fprintf(logfile, "CLIO poll12     "); break; }
			case 0x03400574: { fprintf(logfile, "CLIO poll13     "); break; }
			case 0x03400578: { fprintf(logfile, "CLIO poll14     "); break; }
			case 0x0340057c: { fprintf(logfile, "CLIO poll15     "); break; }
			case 0x034017d0: { fprintf(logfile, "CLIO sema       "); break; }
			case 0x034017d4: { fprintf(logfile, "CLIO semaack    "); break; }
			case 0x034017e0: { fprintf(logfile, "CLIO dspdma     "); break; }
			case 0x034017e4: { fprintf(logfile, "CLIO dspprst0   "); break; }
			case 0x034017e8: { fprintf(logfile, "CLIO dspprst1   "); break; }
			case 0x034017f4: { fprintf(logfile, "CLIO dspppc     "); break; }
			case 0x034017f8: { fprintf(logfile, "CLIO dsppnr     "); break; }
			case 0x034017fc: { fprintf(logfile, "CLIO dsppgw     "); break; }
			case 0x034039dc: { fprintf(logfile, "CLIO dsppclkreld"); break; }
			default: fprintf(logfile, "CLIO ?          "); break;
		}

		if (addr_ >= 0x03400580 && addr_ <= 0x034005bf) {
			if (write) fprintf(logfile, "CLIO CmdFIFO    ");
			else fprintf(logfile, "CLIO StatFIFO   ");
		}
		else if (addr_ >= 0x034005c0 && addr_ <= 0x034005ff) fprintf(logfile, "CLIO DataFIFO   ");
		else if (addr_ >= 0x03401800 && addr_ <= 0x03401fff) fprintf(logfile, "CLIO DSPP  N 32 ");
		else if (addr_ >= 0x03402000 && addr_ <= 0x03402fff) fprintf(logfile, "CLIO DSPP  N 16 ");
		else if (addr_ >= 0x03403000 && addr_ <= 0x034031ff) fprintf(logfile, "CLIO DSPP EI 32 ");
		else if (addr_ >= 0x03403400 && addr_ <= 0x034037ff) fprintf(logfile, "CLIO DSPP EI 16 ");
		else if (addr_ >= 0x0340C000 && addr_ <= 0x0340C000) fprintf(logfile, "CLIO unc_rev    ");
		else if (addr_ >= 0x0340C000 && addr_ <= 0x0340C004) fprintf(logfile, "CLIO unc_soft_rv");
		else if (addr_ >= 0x0340C000 && addr_ <= 0x0340C008) fprintf(logfile, "CLIO unc_addr   ");
		else if (addr_ >= 0x0340C000 && addr_ <= 0x0340C00C) fprintf(logfile, "CLIO unc_rom    ");
	}
}

int verilate() {
	if (!Verilated::gotFinish()) {
		if (main_time < 50) {
			top->reset_n = 0;   	// Assert reset (active LOW)
		}
		if (main_time == 50) {		// Do == here, so we can still reset it in the main loop.
			top->reset_n = 1;		// Deassert reset./
		}
		//if ((main_time & 1) == 1) {
		//top->rootp->sys_clk = 1;       // Toggle clock
		//}
		//if ((main_time & 1) == 0) {
		//top->rootp->sys_clk = 0;

		pix_count++;

		uint32_t word_addr = (top->o_wb_adr)>>2;

		// Handle writes to Main RAM, with byte masking...
		if (top->o_wb_adr>=0x00000000 && top->o_wb_adr<=0x001fffff && top->o_wb_stb && top->o_wb_we) {		// 2MB masked.
			//printf("Main RAM Write!  Addr:0x%08X  Data:0x%08X  BE:0x%01X\n", top->o_wb_adr&0xFFFFF, top->o_wb_dat, top->o_wb_sel);
			uint8_t ram_wbyte0 = (top->o_wb_dat>>24) & 0xff;
			uint8_t ram_wbyte1 = (top->o_wb_dat>>16) & 0xff;
			uint8_t ram_wbyte2 = (top->o_wb_dat>>8)  & 0xff;
			uint8_t ram_wbyte3 = (top->o_wb_dat>>0)  & 0xff;
			if ( top->o_wb_sel&8 ) ram_ptr[ (top->o_wb_adr+0)&0x1fffff ] = ram_wbyte0;
			if ( top->o_wb_sel&4 ) ram_ptr[ (top->o_wb_adr+1)&0x1fffff ] = ram_wbyte1;
			if ( top->o_wb_sel&2 ) ram_ptr[ (top->o_wb_adr+2)&0x1fffff ] = ram_wbyte2;
			if ( top->o_wb_sel&1 ) ram_ptr[ (top->o_wb_adr+3)&0x1fffff ] = ram_wbyte3;
		}
		uint32_t ram_merged = ((ram_ptr[ (top->o_wb_adr+0)&0x1fffff ]<<24) & 0xFF000000) |
							  ((ram_ptr[ (top->o_wb_adr+1)&0x1fffff ]<<16) & 0x00FF0000) |
							  ((ram_ptr[ (top->o_wb_adr+2)&0x1fffff ]<<8) &  0x0000FF00) |
							  ((ram_ptr[ (top->o_wb_adr+3)&0x1fffff ]<<0) &  0x000000FF);

		uint32_t temp_word;

		// Handle writes to VRAM, with byte masking...
		if (top->o_wb_adr>=0x00200000 && top->o_wb_adr<=0x002FFFFF && top->o_wb_stb && top->o_wb_we) {		// 1MB Masked.
			//printf("VRAM Write!  Addr:0x%08X  Data:0x%08X  BE:0x%01X\n", top->o_wb_adr&0xFFFFF, top->o_wb_dat, top->o_wb_sel);
			temp_word = vram_ptr[word_addr&0x3FFFF];
			if ( top->o_wb_sel&8 ) vram_ptr[word_addr&0x3FFFF] = temp_word&0x00FFFFFF | top->o_wb_dat&0xFF000000;	// MSB byte.
			temp_word = vram_ptr[word_addr&0x3FFFF];
			if ( top->o_wb_sel&4 ) vram_ptr[word_addr&0x3FFFF] = temp_word&0xFF00FFFF | top->o_wb_dat&0x00FF0000;
			temp_word = vram_ptr[word_addr&0x3FFFF];
			if ( top->o_wb_sel&2 ) vram_ptr[word_addr&0x3FFFF] = temp_word&0xFFFF00FF | top->o_wb_dat&0x0000FF00;
			temp_word = vram_ptr[word_addr&0x3FFFF];
			if ( top->o_wb_sel&1 ) vram_ptr[word_addr&0x3FFFF] = temp_word&0xFFFFFF00 | top->o_wb_dat&0x000000FF;	// LSB byte.
		}

		// Handle writes to NVRAM...
		if (top->o_wb_adr>=0x03140000 && top->o_wb_adr<=0x0315ffff && top->o_wb_stb && top->o_wb_we) {		// 128KB Masked.
			//printf("NVRAM Write!  Addr:0x%08X  Data:0x%08X  BE:0x%01X\n", top->o_wb_adr&0x1FFFF, top->o_wb_dat, top->o_wb_sel);
			temp_word = nvram_ptr[word_addr&0x7FFF];
			if ( top->o_wb_sel&8 ) nvram_ptr[word_addr&0x7FFF] = temp_word&0x00FFFFFF | top->o_wb_dat&0xFF000000;	// MSB byte.
			temp_word = nvram_ptr[word_addr&0x7FFF];
			if ( top->o_wb_sel&4 ) nvram_ptr[word_addr&0x7FFF] = temp_word&0xFF00FFFF | top->o_wb_dat&0x00FF0000;
			temp_word = nvram_ptr[word_addr&0x7FFF];
			if ( top->o_wb_sel&2 ) nvram_ptr[word_addr&0x7FFF] = temp_word&0xFFFF00FF | top->o_wb_dat&0x0000FF00;
			temp_word = nvram_ptr[word_addr&0x7FFF];
			if ( top->o_wb_sel&1 ) nvram_ptr[word_addr&0x7FFF] = temp_word&0xFFFFFF00 | top->o_wb_dat&0x000000FF;	// LSB byte.
		}

		uint32_t rom_merged = ((rom_ptr[ (top->o_wb_adr+0)&0xfffff ]<<24) & 0xFF000000) |
							  ((rom_ptr[ (top->o_wb_adr+1)&0xfffff ]<<16) & 0x00FF0000) |
							  ((rom_ptr[ (top->o_wb_adr+2)&0xfffff ]<<8) &  0x0000FF00) |
							  ((rom_ptr[ (top->o_wb_adr+3)&0xfffff ]<<0) &  0x000000FF);

		uint32_t rom2_merged = ((rom2_ptr[ (top->o_wb_adr+0)&0xfffff ]<<24) & 0xFF000000) |
							   ((rom2_ptr[ (top->o_wb_adr+1)&0xfffff ]<<16) & 0x00FF0000) |
							   ((rom2_ptr[ (top->o_wb_adr+2)&0xfffff ]<<8) &  0x0000FF00) |
							   ((rom2_ptr[ (top->o_wb_adr+3)&0xfffff ]<<0) &  0x000000FF);

		//cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__o_pc;
		cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__i_pc_ff;

		//trace = 1;

		if (top->i_wb_ack) next_ack = 0;
		top->i_wb_ack = next_ack;

		if (top->o_wb_stb) next_ack = 1;

		if (top->o_wb_stb && top->i_wb_ack) {
			do_printf = 1;
			//if (cur_pc==0x03000EF4) trace = 1;

			if (trace) {
				//if ((cur_pc>(old_pc+8)) || (cur_pc<(old_pc-8))) {
				if (cur_pc!=old_pc) {
					fprintf(logfile, "PC: 0x%08X \n", cur_pc);
					old_pc = cur_pc;
				}
			}

			//if (trace) fprintf(logfile, "PC: 0x%08X \n", cur_pc);

			if (top->o_wb_adr >= 0x03100000 && top->o_wb_adr <= 0x034FFFFF /*&& !(top->o_wb_adr==0x03400044)*/) fprintf(logfile, "Addr: 0x%08X ", top->o_wb_adr);

			// Tech manual suggests "Any write to this area will unmap the BIOS".
			//if (top->o_wb_adr >= 0x00000000 && top->o_wb_dat <= 0x001FFFFF && top->o_wb_we) map_bios = 0;
			if (top->o_wb_adr>=0x00000000 && top->o_wb_dat<=0x00000000 && top->o_wb_we) map_bios = 0;

			// Main RAM (or overlaid BIOS) reads...
			if (top->o_wb_adr >= 0x00000118 && top->o_wb_adr <= 0x00000118) top->i_wb_dat = 0xE3A00000;	// MOV R0, #0. Clear R0 ! TESTING! Skip big delay.
			//else if (top->o_wb_adr >= 0x00014f6c && top->o_wb_adr <= 0x00014f6f) top->i_wb_dat = 0xE1A00000;	// NOP ! SWI Overrun thing.
			//else if (top->o_wb_adr>=0x00000050 && top->o_wb_adr<=0x00000050) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) TESTING !
			//else if (top->o_wb_adr>=0x0000095C && top->o_wb_adr<=0x000009F0) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) TESTING !
			else if (top->o_wb_adr >= 0x00000000 && top->o_wb_adr <= 0x001FFFFF) {
				if (map_bios && rom_select == 0) top->i_wb_dat = rom_merged;		// BIOS is mapped into main RAM space at start-up.
				else if (map_bios && rom_select == 1) top->i_wb_dat = rom2_merged;	// ROM2 is usually the Kanji font ROM, mapped when rom_select==1.
				else { top->i_wb_dat = ram_merged; }
			}

			else if (top->o_wb_adr >= 0x00200000 && top->o_wb_adr <= 0x002FFFFF) { /*fprintf(logfile, "VRAM            ");*/ top->i_wb_dat = vram_ptr[word_addr & 0x3FFFF]; /*if (top->o_wb_we) vram_ptr[word_addr&0x7FFFF] = top->o_wb_dat;*/ }

			// BIOS reads...
			//else if (top->o_wb_adr>=0x03000218 && top->o_wb_adr<=0x03000220) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip t2_testmemory and BeepsAndHold. TESTING!

			//else if (top->o_wb_adr >= 0x03000510 && top->o_wb_adr <= 0x03000510) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip another delay.
			//else if (top->o_wb_adr >= 0x03000504 && top->o_wb_adr <= 0x0300050C) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip another delay.
			//else if (top->o_wb_adr>=0x03000340 && top->o_wb_adr<=0x03000340) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip endless loop on mem size check fail.
			//else if (top->o_wb_adr >= 0x030006a8 && top->o_wb_adr <= 0x030006b0) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip test_vram_svf. TESTING !!
			//else if (top->o_wb_adr>=0x030008E0 && top->o_wb_adr<=0x03000944) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0)
			//else if (top->o_wb_adr>=0x0300056C && top->o_wb_adr<=0x0300056C) top->i_wb_dat = 0xE888001F;	// STM fix. TESTING !!
			else if (top->o_wb_adr >= 0x03000000 && top->o_wb_adr <= 0x030FFFFF) { /*fprintf(logfile, "BIOS            ");*/ top->i_wb_dat = /*(rom_select==0) ?*/ rom_merged /*: rom2_merged*/; }

			else if (top->o_wb_adr >= 0x03100000 && top->o_wb_adr <= 0x03100020) { /*fprintf(logfile, "Brooktree       ");*/ top->i_wb_dat = 0xBADACCE5; }

			else if (top->o_wb_adr >= 0x03140000 && top->o_wb_adr <= 0x0315FFFF) { /*fprintf(logfile, "NVRAM           ");*/ }
			else if (top->o_wb_adr == 0x03180000 && top->o_wb_we) { /*fprintf(logfile, "DiagPort        ");*/ shift_reg = 0x2000; }
			else if (top->o_wb_adr == 0x03180000 && !top->o_wb_we) { /*fprintf(logfile, "DiagPort        ");*/ top->i_wb_dat = 0x00000000; }
			//else if (top->o_wb_adr==0x03180000 && !top->o_wb_we) { fprintf(logfile, "DiagPort        "); top->i_wb_dat = (shift_reg&0x8000)>>15; shift_reg=shift_reg<<1; }
			else if (top->o_wb_adr >= 0x03180004 && top->o_wb_adr <= 0x031BFFFF) { /*fprintf(logfile, "Slow Bus        ");*/ }
			else if (top->o_wb_adr >= 0x03200000 && top->o_wb_adr <= 0x0320FFFF) { /*fprintf(logfile, "VRAM SVF        ");*/ top->i_wb_dat = 0xBADACCE5; }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x032F0000 && top->o_wb_adr <= 0x032FFFFF) { /*fprintf(logfile, "Unknown         ");*/ top->i_wb_dat = 0xBADACCE5; }	// Dummy reads for now.

			top->i_wb_dat = (top->rootp->core_3do__DOT__madam_cs) ? top->rootp->core_3do__DOT__madam_dout :
							(top->rootp->core_3do__DOT__clio_cs)  ? top->rootp->core_3do__DOT__clio_dout :
							(top->rootp->core_3do__DOT__svf_cs)   ? 0xBADACCE5 :
							(top->rootp->core_3do__DOT__svf2_cs)  ? 0x00000000 :
							top->i_wb_dat;	// Else, take input from the C code above (for BIOS, DRAM, VRAM, NVRAM etc.)

			print_to_log(top->o_wb_adr, top->o_wb_dat, top->o_wb_we, cur_pc); // Address, Value, 0=read/1=write.
			if (top->o_wb_adr >= 0x03100000 && top->o_wb_adr <= 0x034FFFFF) {
				if (top->o_wb_we) fprintf(logfile, "Write: 0x%08X  (PC: 0x%08X)\n", top->o_wb_dat, cur_pc);
				else fprintf(logfile, " Read: 0x%08X  (PC: 0x%08X)\n", top->i_wb_dat, cur_pc);
			}
		}

		if (top->rootp->core_3do__DOT__clio_inst__DOT__vcnt==top->rootp->core_3do__DOT__clio_inst__DOT__vcnt_max && top->rootp->core_3do__DOT__clio_inst__DOT__hcnt==0) {
			frame_count++;
			process_vdl();
		}

		/*
		if (line_count==vcnt_max) {
			line_count=0;
			field = !field;
			frame_count++;
			process_vdl();
		}
			else if ( (main_time&0x3FF)==0 ) {
			line_count++;
			if ( line_count==(vint0_reg&0x7FF) ) irq0 |= 1;
			if ( line_count==(vint1_reg&0x7FF) ) irq0 |= 2;
		}
		*/

		//top->i_firq = (irq0&2) && (mask0&2);

		// bit 00 - VINT0
		// bit 01 - VINT1 (VSyncTimerFirq, ControlPort, SPORTfirq, GraphicsFirq is hung here)

		/*
		// Write VGA output to a file. RAW RGB!
		rgb[0] = top->VGA_R;
		rgb[1] = top->VGA_G;
		rgb[2] = top->VGA_B;
		//fwrite(rgb, 1, 3, vgap);		// Write 24-bit values to the file.
		uint32_t vga_addr = (line_count * 1024) + pix_count;
		if (vga_addr <= vga_size) vga_ptr[vga_addr] = (rgb[0] << 24) | (rgb[1] << 16) | (rgb[2] << 8) | 0xCC;
		*/

		//for (int i = 0; i < 100; i++) disp_ptr[1000 + i] = 0xFF00FF00;

		/*
		if (top->sega_saturn_vdp1__DOT__fb0_we) {
		//rgb[0] = (top->sega_saturn_vdp1__DOT__fb0_dout & 0x0F00) >> 4;	// [4:0] Red.
		//rgb[1] = (top->sega_saturn_vdp1__DOT__fb0_dout & 0x00F0) >> 0;	// [9:5] Green.
		//rgb[2] = (top->sega_saturn_vdp1__DOT__fb0_dout & 0x000F) << 4;	// [14:10] Blue.
		rgb[0] = (top->sega_saturn_vdp1__DOT__fb0_dout & 0x001F) << 3;	// [4:0] Red.
		rgb[1] = (top->sega_saturn_vdp1__DOT__fb0_dout & 0x03E0) >> 2;	// [9:5] Green.
		rgb[2] = (top->sega_saturn_vdp1__DOT__fb0_dout & 0x7C00) >> 7;	// [14:10] Blue.
		disp_ptr[top->sega_saturn_vdp1__DOT__fb0_addr] = 0xff<<24 | rgb[2] << 16 | rgb[1] << 8 | rgb[0];	// Our debugger framebuffer is in the 32-bit ABGR format.
		//disp_ptr[top->sega_saturn_vdp1__DOT__fb0_addr] = 0xFF00FF00;

		if ((frame_count & 1) == 0) {
		fb0_ptr[top->sega_saturn_vdp1__DOT__fb0_addr] = top->sega_saturn_vdp1__DOT__fb0_dout;
		}
		//else fb0_ptr[top->system_top__DOT__GPU_addr] = 0xFFFF0000;	// Force a colour, because it's broken atm, and I can't see anything. ElectronAsh.
		}
		*/

		/*
		if (prev_hsync && !top->VGA_HS) {
		//printf("Line Count: %d\n", line_count);
		//printf("Pix count: %d\n", pix_count);
		line_count++;
		pix_count = 0;
		}
		prev_hsync = top->VGA_HS;

		if (prev_vsync && !top->VGA_VS) {
		frame_count++;
		line_count = 0;
		printf("Frame: %06d  VSync! \n", frame_count);

		if (frame_count > 46) {
		printf("Dumping framebuffer to vga_out.raw!\n");
		char vga_filename[40];
		sprintf(vga_filename, "vga_frame_%d.raw", frame_count);
		vgap = fopen(vga_filename, "wb");
		if (vgap != NULL) {
		printf("\nOpened %s for writing OK.\n", vga_filename);
		}
		else {
		printf("\nCould not open %s for writing!\n\n", vga_filename);
		return 0;
		};
		fseek(vgap, 0L, SEEK_SET);
		}

		for (int i = 0; i < (1600 * 521); i++) {	// Pixels per line * total lines.
		rgb[0] = (fb0_ptr[i] & 0x001F) << 3;	// [4:0] Red.
		rgb[1] = (fb0_ptr[i] & 0x03E0) >> 2;	// [9:5] Green.
		rgb[2] = (fb0_ptr[i] & 0x7C00) >> 7;	// [14:10] Blue.

		//rgb[0] = (vga_ptr[i] & 0xFF0000) >> 24;
		//rgb[1] = (vga_ptr[i] & 0x00FF00) >> 16;
		//rgb[2] = (vga_ptr[i] & 0x0000FF) >> 8;

		//if (frame_count > =75) fwrite(rgb, 1, 3, vgap);	// Write pixels to the file.
		if (frame_count >= 75) fwrite(rgb, 3, 1, vgap);	// Write pixels to the file.
		}
		if (frame_count > 46) fclose(vgap);

		//printf("pc: %08X  addr: %08X  inst: %08X\n", top->pc << 2, top->interp_addr, top->inst);
		}
		prev_vsync = top->VGA_VS;

		//if (top->VGA_we==1) printf("VGA_we is High!\n");

		//if (top->SRAM_DQ > 0) printf("SRAM_DQ is High!!!\n");
		//if (top->VGA_R > 0 || top->VGA_G > 0 || top->VGA_B > 0) printf("VGA is High!!!\n");
		*/

		main_time++;            // Time passes...

		top->sys_clk = 0;
		top->eval();            // Evaluate model!
		top->sys_clk = 1;
		top->eval();            // Evaluate model!

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
bit 03: Timer0.F Interrupts from timers, only possible from odd (highest in pairs)
bit 04: Timer0.D
bit 05: Timer0.B
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
bit 29: XBUS DMA transfer complite
bit 30: ??? An empty handler - possibly even a watchdog (if that interrupt is enabled and re-triggered). came, and the previous one was not processed, then reset, huh?)
bit 31 - Indicates that there are more interrupts in register 0x0340 0060
*/


static MemoryEditor mem_edit_1;
static MemoryEditor mem_edit_2;
static MemoryEditor mem_edit_3;
static MemoryEditor mem_edit_4;
static MemoryEditor mem_edit_5;
static MemoryEditor mem_edit_6;
static MemoryEditor mem_edit_7;
static MemoryEditor mem_edit_8;



int main(int argc, char** argv, char** env) {

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
	memset(ram_ptr, 0x00000000, ram_size);
	memset(vram_ptr, 0x00000000, vram_size);
	memset(disp_ptr, 0xff444444, disp_size);

	//memset(vga_ptr,  0xAA, vga_size);

	logfile = fopen("sim_trace.txt", "w");

	FILE *romfile;
	//romfile = fopen("panafz1.bin", "rb");
	romfile = fopen("panafz10.bin", "rb");		// This is the version MAME v226b uses by default, with "mame64 3do".
	//romfile = fopen("panafz10-norsa.bin", "rb");
	//romfile = fopen("sanyotry.bin", "rb");
	//romfile = fopen("goldstar.bin", "rb");
	//if (romfile != NULL) { sprintf(my_string, "\nBIOS file loaded OK.\n");  MyAddLog(my_string); }
	//else { sprintf(my_string, "\nBIOS file not found!\n\n"); MyAddLog(my_string); return 0; }
	//unsigned int file_size;
	fseek(romfile, 0L, SEEK_END);
	file_size = ftell(romfile);
	fseek(romfile, 0L, SEEK_SET);
	fread(rom_ptr, 1, rom_size, romfile);	// Read the whole BIOS file into RAM.

	FILE *rom2file;
	rom2file = fopen("panafz1-kanji.bin", "rb");
	//if (rom2file != NULL) { sprintf(my_string, "\nBIOS file loaded OK.\n");  MyAddLog(my_string); }
	//else { sprintf(my_string, "\nBIOS file not found!\n\n"); MyAddLog(my_string); return 0; }
	//unsigned int file_size;
	fseek(rom2file, 0L, SEEK_END);
	file_size = ftell(rom2file);
	fseek(rom2file, 0L, SEEK_SET);
	fread(rom2_ptr, 1, rom2_size, rom2file);	// Read the whole BIOS file into RAM.

	/*
	FILE *ramfile;
	ramfile = fopen("3do_mem.bin", "rb");
	fseek(ramfile, 0L, SEEK_END);
	file_size = ftell(ramfile);
	fseek(ramfile, 0L, SEEK_SET);
	fread(ram_ptr, 1, ram_size, ramfile);	// Read the whole RAM file into RAM.
	*/

	/*
	FILE *vramfile;
	//vramfile = fopen("3do_vram.bin", "rb");
	vramfile = fopen("3do_vram_smol.bin", "rb");
	fseek(vramfile, 0L, SEEK_END);
	file_size = ftell(vramfile);
	fseek(vramfile, 0L, SEEK_SET);
	fread(vram_ptr, 1, vram_size, vramfile);	// Read the whole RAM file into RAM.
	*/

	top->rootp->core_3do__DOT__matrix_inst__DOT__MI00_in = 0x8002aabb;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI01_in = 0xf00cc243;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI02_in = 0x2222aabb;

	top->rootp->core_3do__DOT__matrix_inst__DOT__MI10_in = 0x44333333;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI11_in = 0xF000aabb;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI11_in = 0x00045226;

	top->rootp->core_3do__DOT__matrix_inst__DOT__MI20_in = 0xc0084526;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI21_in = 0x0000007e;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MI22_in = 0x000c000c;

	top->rootp->core_3do__DOT__matrix_inst__DOT__MV0_in  = 0x00000888;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MV1_in  = 0x44880000;
	top->rootp->core_3do__DOT__matrix_inst__DOT__MV2_in  = 0x00444444;

	// Our state
	bool show_demo_window = true;
	bool show_another_window = false;
	ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

	// Build texture atlas
	int width  = 320;
	int height = 240;

	// Upload texture to graphics system
	D3D11_TEXTURE2D_DESC desc;
	ZeroMemory(&desc, sizeof(desc));
	desc.Width = width;
	desc.Height = height;
	desc.MipLevels = 1;
	desc.ArraySize = 1;
	desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	//desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
	//desc.Format = DXGI_FORMAT_B5G5R5A1_UNORM;
	desc.SampleDesc.Count = 1;
	desc.Usage = D3D11_USAGE_DEFAULT;
	desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

	ID3D11Texture2D *pTexture = NULL;
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
		//desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;	// LERP.
		desc.Filter = D3D11_FILTER_ANISOTROPIC;
		//desc.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;		// Point sampling.
		desc.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
		desc.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
		desc.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
		desc.MipLODBias = 0.f;
		desc.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
		desc.MinLOD = 0.f;
		desc.MaxLOD = 0.f;
		g_pd3dDevice->CreateSamplerState(&desc, &g_pFontSampler);
	}


	bool follow_writes = 0;
	int write_address = 0;

	static bool show_app_console = true;

	bool second_stop = 0;

	// imgui Main loop stuff...
	MSG msg;
	ZeroMemory(&msg, sizeof(msg));
	while (msg.message != WM_QUIT)
	{
		// Poll and handle messages (inputs, window resize, etc.)
		// You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
		// - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application.
		// - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application.
		// Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
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

		// 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
		//if (show_demo_window)
		//	ImGui::ShowDemoWindow(&show_demo_window);

		// 2. Show a simple window that we create ourselves. We use a Begin/End pair to created a named window.
		static float f = 0.1f;
		static int counter = 0;

		ImGui::Begin("Virtual Dev Board v1.0");		// Create a window called "Virtual Dev Board v1.0" and append into it.

		ShowMyExampleAppConsole(&show_app_console);

		//ImGui::Text("Verilator sim running... ROM_ADDR: 0x%05x", top->rootp->ROM_ADDR);               // Display some text (you can use a format strings too)
		//ImGui::Checkbox("Demo Window", &show_demo_window);      // Edit bools storing our window open/close state
		//ImGui::Checkbox("Another Window", &show_another_window);

		//ImGui::SliderFloat("float", &f, 0.0f, 1.0f);            // Edit 1 float using a slider from 0.0f to 1.0f
		//ImGui::ColorEdit3("clear color", (float*)&clear_color); // Edit 3 floats representing a color

		//if (ImGui::Button("Button"))                            // Buttons return true when clicked (most widgets return true when edited/activated)
		//counter++;

		//ImGui::SameLine();
		//ImGui::Text("counter = %d", counter);
		//ImGui::Text("samp_index = %d", samp_index);
		//ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / ImGui::GetIO().Framerate, ImGui::GetIO().Framerate);
		//ImGui::PlotLines("Lines", values, IM_ARRAYSIZE(values), values_offset, "sample", -1.0f, 1.0f, ImVec2(0, 80));
		if (ImGui::Button("RESET")) {
			main_time = 0;
			rom_select = 0;	// Select the BIOS ROM at startup! (not Kanji).
			map_bios = 1;
			field = 1;
			frame_count = 0;
			line_count = 0;
			//vcnt_max = 262;
			memset(disp_ptr, 0xff444444, disp_size);	// Clear the DISPLAY buffer.
			memset(ram_ptr, 0x00000000, ram_size);		// Clear Main RAM.
			memset(vram_ptr, 0x00000000, vram_size);	// Clear VRAM.
		}ImGui::Text("     reset_n: %d", top->rootp->core_3do__DOT__reset_n);

		ImGui::Text("main_time %d", main_time);
		//ImGui::Text("field: %d  frame_count: %d  line_count: %d", field, frame_count, line_count);
		ImGui::Text("frame_count: %d  field: %d hcnt: %04d  vcnt: %d", frame_count, top->rootp->core_3do__DOT__clio_inst__DOT__field, top->rootp->core_3do__DOT__clio_inst__DOT__hcnt, top->rootp->core_3do__DOT__clio_inst__DOT__vcnt);

		/*
		ImGui::Text("Addr:   0x%08X", top->rootp->mem_addr << 2);

		ImGui::Text("PC:     0x%08X", top->rootp->pc << 2);
		if (top->rootp->system_top__DOT__core__DOT__PC__DOT__enable) {
		ImGui::SameLine(150); ImGui::Text("<- WRITE 0x%08X", top->rootp->system_top__DOT__core__DOT__IF_PCIn);
		}

		if (top->rootp->system_top__DOT__core__DOT__PC__DOT__exe_pc_write) {
		ImGui::SameLine(150); ImGui::Text("<- EXE_PC WRITE 0x%08X", top->rootp->system_top__DOT__core__DOT__exe_pc);
		}

		ImGui::Text("Inst:   0x%08X", top->rootp->system_top__DOT__core__DOT__InstMem_In);
		*/

		//if (ImGui::Button("Reset!")) top->rootp->KEY = 0;
		//else top->rootp->KEY = 1;

		ImGui::Checkbox("RUN", &run_enable);

		dump_ram = ImGui::Button("RAM Dump");

		if (dump_ram) {
			FILE *ramdump;
			ramdump = fopen("dramdump.bin", "wb");
			fwrite(ram_ptr, 1, ram_size, ramdump);	// Dump main RAM to a file.
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
		//ImGui::Text("Last SDRAM WRITE. byte_addr: 0x%08X  write_data: 0x%08X  data_ben: 0x%01X\n", last_sdram_byteaddr, last_sdram_writedata, last_sdram_ben);	//  Note sd_data_i is OUT of the sim!

		ImGui::Image(my_tex_id, ImVec2(width*2, height*2), ImVec2(0, 0), ImVec2(1, 1), ImColor(255, 255, 255, 255), ImColor(255, 255, 255, 128));
		ImGui::End();

		/*
		ImGui::Checkbox("Follow Writes", &follow_writes);
		if (follow_writes) write_address = top->rootp->sd_addr << 2;
		*/

		ImGui::Begin("3DO BIOS ROM Editor");
		mem_edit_1.DrawContents(rom_ptr, rom_size, 0);
		ImGui::End();

		ImGui::Begin("3DO Main RAM Editor");
		mem_edit_2.DrawContents(ram_ptr, ram_size, 0);
		ImGui::End();

		ImGui::Begin("3DO VRAM Editor");
		mem_edit_2.DrawContents(vram_ptr, vram_size, 0);
		ImGui::End();

		//if ( (top->rootp->o_wb_cti!=7) || (top->rootp->o_wb_bte!=0) ) { run_enable=0; printf("cti / bte changed!!\n"); }

		if (run_enable) for (int step = 0; step < 2048; step++) {	// Simulates MUCH faster if it's done in batches.
			verilate();												// But, it will affect the update rate of the GUI.

			// Stop on CLIO timer access.
			//if (top->rootp->o_wb_adr>=0x03400100 && top->rootp->o_wb_adr<=0x03400180 && top->rootp->o_wb_we && top->rootp->o_wb_stb) { run_enable=0; break; }

			//Is this a folio we are pointing to now?
			//teq	r9,#0
			//beq	aborttask
			//if (cur_pc==0x0001162c) { run_enable=0; second_stop=1; break; }

			//if (cur_pc==0x03000372) { run_enable=0; second_stop=1; break; }

			//if (cur_pc==0x00010460) { run_enable=0; second_stop=1; break; }

			//if (cur_pc==0x00011624) { run_enable=0; second_stop=1; break; }
			//if (second_stop && top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r9==0) { run_enable=0; break; }

			//if (top->rootp->core_3do__DOT__zap_top_inst__DOT__i_fiq) { run_enable=0; break; }
		}
		else {
			if (single_step) verilate();
			if (multi_step) for (int step = 0; step < multi_step_amount; step++) verilate();
		}


		ImGui::Begin("ARM Registers");
		ImGui::Text("     reset_n: %d", top->rootp->core_3do__DOT__reset_n);
		ImGui::Text("    o_wb_adr: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__o_wb_adr);
		ImGui::SameLine();
		if (top->rootp->o_wb_adr>=0x00000000 && top->rootp->o_wb_adr<=0x001FFFFF) { if (map_bios) ImGui::Text("  BIOS (mapped)"); else ImGui::Text("    Main RAM    "); }
		else if (top->rootp->o_wb_adr>=0x00200000 && top->rootp->o_wb_adr<=0x003FFFFF) ImGui::Text("     VRAM      ");
		else if (top->rootp->o_wb_adr>=0x03000000 && top->rootp->o_wb_adr<=0x030FFFFF) ImGui::Text("     BIOS      ");
		else if (top->rootp->o_wb_adr>=0x03100000 && top->rootp->o_wb_adr<=0x0313FFFF) ImGui::Text("     Brooktree ");
		else if (top->rootp->o_wb_adr>=0x03140000 && top->rootp->o_wb_adr<=0x0315FFFF) ImGui::Text("     NVRAM     ");
		else if (top->rootp->o_wb_adr==0x03180000) ImGui::Text("       DiagPort  ");
		else if (top->rootp->o_wb_adr>=0x03180004 && top->rootp->o_wb_adr<=0x031BFFFF) ImGui::Text("  Slow Bus     ");
		else if (top->rootp->o_wb_adr>=0x03200000 && top->rootp->o_wb_adr<=0x0320FFFF) ImGui::Text("     VRAM SVF  ");
		else if (top->rootp->o_wb_adr>=0x03300000 && top->rootp->o_wb_adr<=0x033FFFFF) ImGui::Text("     MADAM     ");
		else if (top->rootp->o_wb_adr>=0x03400000 && top->rootp->o_wb_adr<=0x034FFFFF) ImGui::Text("     CLIO      ");
		else { ImGui::Text("    Unknown    "); run_enable = 0; trace = 1; }

		ImGui::Text("    i_wb_dat: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__i_wb_dat);
		ImGui::Text("    o_wb_dat: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__o_wb_dat);
		ImGui::Text("     o_wb_we: %d", top->o_wb_we); ImGui::SameLine(); if (!top->rootp->o_wb_we) ImGui::Text(" Read"); else ImGui::Text(" Write");
		ImGui::Text("    o_wb_cti: 0x%01X", top->rootp->core_3do__DOT__zap_top_inst__DOT__o_wb_cti);
		ImGui::Text("    o_wb_bte: 0x%01X", top->rootp->core_3do__DOT__zap_top_inst__DOT__o_wb_bte);
		ImGui::Text("    o_wb_sel: 0x%01X", top->o_wb_sel);
		ImGui::Text("    o_wb_stb: %d", top->o_wb_stb);
		ImGui::Text("    i_wb_ack: %d", top->i_wb_ack);
		ImGui::Text("  i_mem_addr: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__i_mem_address_ff2);
		ImGui::Text("    o_wb_adr: 0x%08X", top->o_wb_adr);
		ImGui::Separator();
		ImGui::Text("       i_fiq: %d", top->rootp->core_3do__DOT__zap_top_inst__DOT__i_fiq); 
		/*
		ImGui::Text("       sbyte: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__sbyte);
		ImGui::Text("       ubyte: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__ubyte);
		ImGui::Text("       shalf: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__shalf);
		ImGui::Text("       uhalf: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__uhalf);
		ImGui::Text(" transform d: 0x%08X", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__transform_function__DOT__d);
		*/

		/*
		ImGui::Text("         op1: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__op1);
		ImGui::Text("         op2: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__op2);
		ImGui::Text("      opcode: 0x%01X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__opcode);
		*/

		uint32_t reg_src = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__o_alu_source_ff;
		uint32_t reg_dst = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__o_destination_index_ff;
		ImVec4 reg_col [40];
		for (int i = 0; i < 40; i++) {
			reg_col[i] = ImVec4(1.0f,1.0f,1.0f,1.0f);
			if (reg_src==i) reg_col[i] = ImVec4(0.0f,1.0f,0.0f,1.0f);	// Source reg = GREEN.
			if (reg_dst==i) reg_col[i] = ImVec4(1.0f,0.0f,0.0f,1.0f);	// Dest reg = RED.
		}

		uint32_t arm_reg[40];
		for (int i = 0; i < 40; i++) {
			arm_reg[i] = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__mem[i];
		}

		ImGui::Separator();
		ImGui::Text("          PC: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_issue_main__DOT__o_pc_ff);
		ImGui::TextColored(ImVec4(reg_col[0]),  "          R0: 0x%08X", arm_reg[0]);
		ImGui::TextColored(ImVec4(reg_col[1]),  "          R1: 0x%08X", arm_reg[1]);
		ImGui::TextColored(ImVec4(reg_col[2]),  "          R2: 0x%08X", arm_reg[2]);
		ImGui::TextColored(ImVec4(reg_col[3]),  "          R3: 0x%08X", arm_reg[3]);
		ImGui::TextColored(ImVec4(reg_col[4]),  "          R4: 0x%08X", arm_reg[4]);
		ImGui::TextColored(ImVec4(reg_col[5]),  "          R5: 0x%08X", arm_reg[5]);
		ImGui::TextColored(ImVec4(reg_col[6]),  "          R6: 0x%08X", arm_reg[6]);
		ImGui::TextColored(ImVec4(reg_col[7]),  "          R7: 0x%08X", arm_reg[7]);
		ImGui::TextColored(ImVec4(reg_col[8]),  "          R8: 0x%08X", arm_reg[8]);
		ImGui::TextColored(ImVec4(reg_col[9]),  "          R9: 0x%08X", arm_reg[9]);
		ImGui::TextColored(ImVec4(reg_col[10]), "         R10: 0x%08X", arm_reg[10]);
		ImGui::TextColored(ImVec4(reg_col[11]), "         R11: 0x%08X", arm_reg[11]);
		ImGui::TextColored(ImVec4(reg_col[12]), "         R12: 0x%08X", arm_reg[12]);
		ImGui::TextColored(ImVec4(reg_col[13]), "      SP R13: 0x%08X", arm_reg[13]);
		ImGui::TextColored(ImVec4(reg_col[14]), "      LR R14: 0x%08X", arm_reg[14]);
		//ImGui::TextColored(ImVec4(reg_col[15]), " unused? R15: 0x%08X", arm_reg[15]);
		//ImGui::Text("reg_src: %d", reg_src);
		//ImGui::Text("reg_dst: %d", reg_dst);
		ImGui::Separator();

		uint32_t cpsr = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__alu_cpsr_nxt;
		// Pause the sim, on certain cpsr errors.
		// (3DO code should never enter Thumb mode, as the ARM60 doesn't have Thumb instructions, AFAIK. ElectronAsh).
		if ( (cpsr&0x1F) == 0b10111)  {fprintf(logfile, "ABORT Detected!  PC: 0x%08X \n", cur_pc); run_enable = 0;};
		if ( (cpsr&0x20) == 1 ) {fprintf(logfile, "THUMB Detected!  PC: 0x%08X \n", cur_pc); run_enable = 0;};

		ImGui::Text("        CPSR: 0x%08X", cpsr);
		ImGui::Text("        bits: %d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d",
			(cpsr&0x80000000)>>31, (cpsr&0x40000000)>>30, (cpsr&0x20000000)>>29, (cpsr&0x10000000)>>28, (cpsr&0x08000000)>>27, (cpsr&0x04000000)>>26, (cpsr&0x02000000)>>25, (cpsr&0x01000000)>>24,
			(cpsr&0x00800000)>>23, (cpsr&0x00400000)>>22, (cpsr&0x00200000)>>21, (cpsr&0x00100000)>>20, (cpsr&0x00080000)>>19, (cpsr&0x00040000)>>18, (cpsr&0x00020000)>>17, (cpsr&0x00010000)>>16,
			(cpsr&0x00008000)>>15, (cpsr&0x00004000)>>14, (cpsr&0x00002000)>>13, (cpsr&0x00001000)>>12, (cpsr&0x00000800)>>11, (cpsr&0x00000400)>>10, (cpsr&0x00000200)>>9,  (cpsr&0x00000100)>>8,
			(cpsr&0x00000080)>>7,  (cpsr&0x00000040)>>6,  (cpsr&0x00000020)>>5,  (cpsr&0x00000010)>>4,  (cpsr&0x00000008)>>3,  (cpsr&0x00000004)>>2,  (cpsr&0x00000002)>>1,  (cpsr&0x00000001)>>0 );
		ImGui::Text("              NZCVQIIJ    GGGGIIIIIIEAIFTMMMMM", cpsr);
		ImGui::Text("                   TT     EEEETTTTTT          ", cpsr);
		ImGui::Separator();
		ImGui::End();

		ImGui::Begin("ARM Secondary regs");
		ImGui::TextColored(ImVec4(reg_col[16]), "         RAZ: 0x%08X", arm_reg[16]);
		ImGui::TextColored(ImVec4(reg_col[17]), "    PHY_CPSR: 0x%08X", arm_reg[17]);
		ImGui::TextColored(ImVec4(reg_col[18]), "         FR8: 0x%08X", arm_reg[18]);
		ImGui::TextColored(ImVec4(reg_col[19]), "         FR9: 0x%08X", arm_reg[19]);
		ImGui::TextColored(ImVec4(reg_col[20]), "        FR10: 0x%08X", arm_reg[20]);
		ImGui::TextColored(ImVec4(reg_col[21]), "        FR11: 0x%08X", arm_reg[21]);
		ImGui::TextColored(ImVec4(reg_col[22]), "        FR12: 0x%08X", arm_reg[22]);
		ImGui::TextColored(ImVec4(reg_col[23]), "        FR13: 0x%08X", arm_reg[23]);
		ImGui::TextColored(ImVec4(reg_col[24]), "        FR14: 0x%08X", arm_reg[24]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[25]), "       IRQ13: 0x%08X", arm_reg[25]);
		ImGui::TextColored(ImVec4(reg_col[26]), "       IRQ14: 0x%08X", arm_reg[26]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[27]), "       SVC13: 0x%08X", arm_reg[27]);
		ImGui::TextColored(ImVec4(reg_col[28]), "       SVC14: 0x%08X", arm_reg[28]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[29]), "       UND13: 0x%08X", arm_reg[29]);
		ImGui::TextColored(ImVec4(reg_col[30]), "       UND14: 0x%08X", arm_reg[30]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[31]), "       ABT13: 0x%08X", arm_reg[31]);
		ImGui::TextColored(ImVec4(reg_col[32]), "       ABT14: 0x%08X", arm_reg[32]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[33]), "        DUM0: 0x%08X", arm_reg[33]);
		ImGui::TextColored(ImVec4(reg_col[34]), "        DUM1: 0x%08X", arm_reg[34]);
		ImGui::Separator();
		ImGui::TextColored(ImVec4(reg_col[35]), "    FIQ_SPSR: 0x%08X", arm_reg[35]);
		ImGui::TextColored(ImVec4(reg_col[36]), "    IRQ_SPSR: 0x%08X", arm_reg[36]);
		ImGui::TextColored(ImVec4(reg_col[37]), "    SVC_SPSR: 0x%08X", arm_reg[37]);
		ImGui::TextColored(ImVec4(reg_col[38]), "    UND_SPSR: 0x%08X", arm_reg[38]);
		ImGui::TextColored(ImVec4(reg_col[39]), "    ABT_SPSR: 0x%08X", arm_reg[39]);
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
		ImGui::Text("      random: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__random);		// 0x3c - read only?
		ImGui::Separator();
		ImGui::Text("   irq0_pend: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq0_pend);		// 0x40/0x44.
		ImGui::Text(" irq0_enable: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq0_enable);	// 0x48/0x4c.
		ImGui::Text("   irq0_trig: %d", top->rootp->core_3do__DOT__clio_inst__DOT__irq0_trig);
		ImGui::Text("        mode: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__mode);			// 0x50/0x54.
		ImGui::Text("     badbits: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__badbits);		// 0x58 - for reading things like DMA fail reasons?
		ImGui::Text("       spare: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__spare);			// 0x5c - ?
		ImGui::Text("   irq1_pend: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq1_pend);		// 0x60/0x64.
		ImGui::Text(" irq1_enable: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__irq1_enable);	// 0x68/0x6c.
		ImGui::Text("   irq1_trig: %d", top->rootp->core_3do__DOT__clio_inst__DOT__irq1_trig);
		ImGui::Separator();
		ImGui::Text("      hdelay: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__hdelay);		// 0x80
		ImGui::Text("   adbio_reg: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg);		// 0x84
		ImGui::Text("      adbctl: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__adbctl);		// 0x88
		ImGui::Separator();
		ImGui::Text("       slack: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__slack);			// 0x220
		ImGui::Text("   dmareqdis: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dmareqdis);		// 0x308
		ImGui::Text("      expctl: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__expctl);		// 0x400
		ImGui::Text("     type0_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__type0_4);		// 0x408
		ImGui::Text("      dipir1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dipir1);		// 0x410
		ImGui::Text("      dipir2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dipir2);		// 0x414
		ImGui::Separator();
		ImGui::Text("    unclerev: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__unclerev);		// 0xc000
		ImGui::Text("unc_soft_rev: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__unc_soft_rev);	// 0xc004
		ImGui::Text("  uncle_addr: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__uncle_addr);	// 0xc008
		ImGui::Text("   uncle_rom: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__uncle_rom);		// 0xc00c
		ImGui::End();

		ImGui::Begin("CLIO Timers");
		ImGui::Text("  timer_count_0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_0);		// 0x100
		ImGui::Text(" timer_backup_0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_0);		// 0x104
		ImGui::Text("  timer_count_1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_1);		// 0x108
		ImGui::Text(" timer_backup_1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_1);		// 0x10c
		ImGui::Text("  timer_count_2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_2);		// 0x110
		ImGui::Text(" timer_backup_2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_2);		// 0x114
		ImGui::Text("  timer_count_3: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_3);		// 0x118
		ImGui::Text(" timer_backup_3: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_3);		// 0x11c
		ImGui::Text("  timer_count_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_4);		// 0x120
		ImGui::Text(" timer_backup_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_4);		// 0x124
		ImGui::Text("  timer_count_5: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_5);		// 0x128
		ImGui::Text(" timer_backup_5: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_5);		// 0x12c
		ImGui::Text("  timer_count_6: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_6);		// 0x130
		ImGui::Text(" timer_backup_6: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_6);		// 0x134
		ImGui::Text("  timer_count_7: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_7);		// 0x138
		ImGui::Text(" timer_backup_7: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_7);		// 0x13c
		ImGui::Text("  timer_count_8: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_8);		// 0x140
		ImGui::Text(" timer_backup_8: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_8);		// 0x144
		ImGui::Text("  timer_count_9: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_9);		// 0x148
		ImGui::Text(" timer_backup_9: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_9);		// 0x14c
		ImGui::Text(" timer_count_10: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_10);		// 0x150
		ImGui::Text("timer_backup_10: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_10);		// 0x154
		ImGui::Text(" timer_count_11: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_11);		// 0x158
		ImGui::Text("timer_backup_11: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_11);		// 0x15c
		ImGui::Text(" timer_count_12: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_12);		// 0x160
		ImGui::Text("timer_backup_12: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_12);		// 0x164
		ImGui::Text(" timer_count_13: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_13);		// 0x168
		ImGui::Text("timer_backup_13: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_13);		// 0x16c
		ImGui::Text(" timer_count_14: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_14);		// 0x170
		ImGui::Text("timer_backup_14: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_14);		// 0x174
		ImGui::Text(" timer_count_15: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_15);		// 0x178
		ImGui::Text("timer_backup_15: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_15);		// 0x17c
		ImGui::Separator();
		ImGui::Text("     timer_ctrl: 0x%016X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_ctrl);		// 0x200,0x204,0x208,0x20c. 64-bits wide?? TODO: How to handle READS of the 64-bit reg?
		ImGui::End();

		ImGui::Begin("CLIO sel regs");
		ImGui::Text(" sel_0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_0);	// 0x500
		ImGui::Text(" sel_1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_1);	// 0x504
		ImGui::Text(" sel_2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_2);	// 0x508
		ImGui::Text(" sel_3: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_3);	// 0x50c
		ImGui::Text(" sel_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_4);	// 0x510
		ImGui::Text(" sel_5: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_5);	// 0x514
		ImGui::Text(" sel_6: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_6);	// 0x518
		ImGui::Text(" sel_7: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_7);	// 0x51c
		ImGui::Text(" sel_8: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_8);	// 0x520
		ImGui::Text(" sel_9: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_9);	// 0x524
		ImGui::Text("sel_10: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_10);	// 0x528
		ImGui::Text("sel_11: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_11);	// 0x52c
		ImGui::Text("sel_12: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_12);	// 0x530
		ImGui::Text("sel_13: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_13);	// 0x534
		ImGui::Text("sel_14: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_14);	// 0x538
		ImGui::Text("sel_15: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_15);	// 0x53c
		ImGui::End();

		ImGui::Begin("CLIO poll regs");
		ImGui::Text(" poll_0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_0);	// 0x540
		ImGui::Text(" poll_1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_1);	// 0x544
		ImGui::Text(" poll_2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_2);	// 0x548
		ImGui::Text(" poll_3: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_3);	// 0x54c
		ImGui::Text(" poll_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_4);	// 0x550
		ImGui::Text(" poll_5: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_5);	// 0x554
		ImGui::Text(" poll_6: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_6);	// 0x558
		ImGui::Text(" poll_7: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_7);	// 0x55c
		ImGui::Text(" poll_8: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_8);	// 0x560
		ImGui::Text(" poll_9: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_9);	// 0x564
		ImGui::Text("poll_10: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_10);	// 0x568
		ImGui::Text("poll_11: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_11);	// 0x56c
		ImGui::Text("poll_12: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_12);	// 0x570
		ImGui::Text("poll_13: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_13);	// 0x574
		ImGui::Text("poll_14: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_14);	// 0x578
		ImGui::Text("poll_15: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_15);	// 0x57c
		ImGui::End();

		ImGui::Begin("CLIO DSP regs");
		ImGui::Text("     sema: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sema);		// 0x17d0
		ImGui::Text("  semaack: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__semaack);	// 0x17d4
		ImGui::Separator();
		ImGui::Text("   dspdma: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspdma);	// 0x17e0
		ImGui::Text(" dspprst0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspprst0);	// 0x17e4
		ImGui::Text(" dspprst1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspprst1);	// 0x17e8
		ImGui::Text("   dspppc: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dspppc);	// 0x17f4
		ImGui::Text("   dsppnr: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dsppnr);	// 0x17f8
		ImGui::Text("   dsppgw: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dsppgw);	// 0x17fc
		ImGui::Separator();
		ImGui::Text("dsppclkreload: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__dsppclkreload);// 0x39dc ?
		ImGui::End();

		ImGui::Begin("MADAM Registers");
		ImGui::Text("        mctl: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__mctl);
		ImGui::Text("      sltime: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__sltime);
		ImGui::Separator();
		ImGui::Text("    vdl_addr: 0x%08X", top->rootp->core_3do__DOT__madam_inst__DOT__vdl_addr);		// 0x580
		ImGui::Separator();
		ImGui::Text(" VDL still in C...");
		ImGui::Text("    vdl_ctl: 0x%08X", vdl_ctl);
		ImGui::Text("   vdl_curr: 0x%08X", vdl_curr);
		ImGui::Text("   vdl_prev: 0x%08X", vdl_prev);
		ImGui::Text("   vdl_next: 0x%08X", vdl_next);
		ImGui::End();


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

		char decode_string[64];
		char issue_string[64];
		char shifter_string[64];
		char alu_string[64];
		char memory_string[64];
		char rb_string[64];
		for (int i=0; i<64; i+=4) {
			decode_string[i+0] = decode_word[ (i>>2) ] >> 0; decode_string[i+1] = decode_word[ (i>>2) ] >> 8; decode_string[i+2] = decode_word[ (i>>2) ] >> 16; decode_string[i+3] = decode_word[ (i>>2) ] >> 24;
			issue_string[i+0] = issue_word[ (i>>2) ] >> 0; issue_string[i+1] = issue_word[ (i>>2) ] >> 8; issue_string[i+2] = issue_word[ (i>>2) ] >> 16; issue_string[i+3] = issue_word[ (i>>2) ] >> 24;
			shifter_string[i+0] = shifter_word[ (i>>2) ] >> 0; shifter_string[i+1] = shifter_word[ (i>>2) ] >> 8; shifter_string[i+2] = shifter_word[ (i>>2) ] >> 16; shifter_string[i+3] = shifter_word[ (i>>2) ] >> 24;
			alu_string[i+0] = alu_word[ (i>>2) ] >> 0; alu_string[i+1] = alu_word[ (i>>2) ] >> 8; alu_string[i+2] = alu_word[ (i>>2) ] >> 16; alu_string[i+3] = alu_word[ (i>>2) ] >> 24;
			memory_string[i+0] = memory_word[ (i>>2) ] >> 0; memory_string[i+1] = memory_word[ (i>>2) ] >> 8; memory_string[i+2] = memory_word[ (i>>2) ] >> 16; memory_string[i+3] = memory_word[ (i>>2) ] >> 24;
			rb_string[i+0] = rb_word[ (i>>2) ] >> 0; rb_string[i+1] = rb_word[ (i>>2) ] >> 8; rb_string[i+2] = rb_word[ (i>>2) ] >> 16; rb_string[i+3] = rb_word[ (i>>2) ] >> 24;
		}

		strrev(decode_string);
		strrev(issue_string);
		strrev(shifter_string);
		strrev(alu_string);
		strrev(memory_string);
		strrev(rb_string);

		ImGui::Begin("Zap Core decompile");
		ImGui::Text("0x%08X: ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__predecode_inst);
		ImGui::Text("    decode: %s", decode_string);
		ImGui::Text("     issue: %s", issue_string);
		ImGui::Text("   shifter: %s", shifter_string);
		ImGui::Text("       alu: %s", alu_string);
		ImGui::Text("    memory: %s", memory_string);
		ImGui::Text("        rb: %s", rb_string);
		ImGui::End();


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
