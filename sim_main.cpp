#include <iostream>
#include <fstream>
#include <string>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

//#include <atomic>
//#include <fstream>

#include "wavedrom.h"
WaveDrom waveDrom;
static const bool GENERATE_JSON = false;

#include <verilated.h>

#include "Vcore_3do___024root.h"
#include "Vcore_3do.h"


#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"
#include <d3d11.h>
#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>
#include <tchar.h>

#include "imgui_memory_editor.h"

FILE *logfile;


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

bool trig_irq = 0;
bool trig_fiq = 0;

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

unsigned int rom_size = 1024 * 256 * 4;		// 1MB. (32-bit wide).
uint32_t *rom_ptr = (uint32_t *) malloc(rom_size);

unsigned int rom2_size = 1024 * 256 * 4;		// 1MB. (32-bit wide).
uint32_t *rom2_ptr = (uint32_t *) malloc(rom2_size);

unsigned int ram_size = 1024 * 512 * 4;		// 2MB. (32-bit wide).
uint32_t *ram_ptr = (uint32_t *) malloc(ram_size);

unsigned int vram_size = 1024 * 256 * 4;	// 1MB. (32-bit wide).
uint32_t *vram_ptr = (uint32_t *)malloc(vram_size);

unsigned int nvram_size = 1024 * 128;		// 128KB?
uint32_t *nvram_ptr = (uint32_t *) malloc(nvram_size);

unsigned int disp_size = 1024 * 1024 * 4;	// 4MB. (32-bit wide). Sim display window.
uint32_t *disp_ptr = (uint32_t *)malloc(disp_size);


double sc_time_stamp () {	// Called by $time in Verilog.
	return main_time;
}


ImVector<char*>       Items;
static char* Strdup(const char *str) { size_t len = strlen(str) + 1; void* buf = malloc(len); IM_ASSERT(buf); return (char*)memcpy(buf, (const void*)str, len); }

void    MyAddLog(const char* fmt, ...) IM_FMTARGS(2)
{
	// FIXME-OPT
	char buf[1024];
	va_list args;
	va_start(args, fmt);
	vsnprintf(buf, IM_ARRAYSIZE(buf), fmt, args);
	buf[IM_ARRAYSIZE(buf) - 1] = 0;
	va_end(args);
	Items.push_back(Strdup(buf));
}

// Demonstrate creating a simple console window, with scrolling, filtering, completion and history.
// For the console example, here we are using a more C++ like approach of declaring a class to hold the data and the functions.
struct MyExampleAppConsole
{
	char                  InputBuf[256];
	ImVector<const char*> Commands;
	ImVector<char*>       History;
	int                   HistoryPos;    // -1: new line, 0..History.Size-1 browsing history.
	ImGuiTextFilter       Filter;
	bool                  AutoScroll;
	bool                  ScrollToBottom;

	MyExampleAppConsole()
	{
		ClearLog();
		memset(InputBuf, 0, sizeof(InputBuf));
		HistoryPos = -1;
		Commands.push_back("HELP");
		Commands.push_back("HISTORY");
		Commands.push_back("CLEAR");
		Commands.push_back("CLASSIFY");  // "classify" is only here to provide an example of "C"+[tab] completing to "CL" and displaying matches.
		AutoScroll = true;
		ScrollToBottom = false;
		MyAddLog("3DO Verilator - Sim start");
		MyAddLog("");
	}
	~MyExampleAppConsole()
	{
		ClearLog();
		for (int i = 0; i < History.Size; i++)
			free(History[i]);
	}

	// Portable helpers
	static int   Stricmp(const char* str1, const char* str2) { int d; while ((d = toupper(*str2) - toupper(*str1)) == 0 && *str1) { str1++; str2++; } return d; }
	static int   Strnicmp(const char* str1, const char* str2, int n) { int d = 0; while (n > 0 && (d = toupper(*str2) - toupper(*str1)) == 0 && *str1) { str1++; str2++; n--; } return d; }
	//	static char* Strdup(const char *str) { size_t len = strlen(str) + 1; void* buf = malloc(len); IM_ASSERT(buf); return (char*)memcpy(buf, (const void*)str, len); }
	static void  Strtrim(char* str) { char* str_end = str + strlen(str); while (str_end > str && str_end[-1] == ' ') str_end--; *str_end = 0; }

	void    ClearLog()
	{
		for (int i = 0; i < Items.Size; i++)
			free(Items[i]);
		Items.clear();
	}

	/*
	void    MyAddLog(const char* fmt, ...) IM_FMTARGS(2)
	{
	// FIXME-OPT
	char buf[1024];
	va_list args;
	va_start(args, fmt);
	vsnprintf(buf, IM_ARRAYSIZE(buf), fmt, args);
	buf[IM_ARRAYSIZE(buf) - 1] = 0;
	va_end(args);
	Items.push_back(Strdup(buf));
	}
	*/

	void    Draw(const char* title, bool* p_open)
	{
		ImGui::SetNextWindowSize(ImVec2(520, 600), ImGuiCond_FirstUseEver);
		if (!ImGui::Begin(title, p_open))
		{
			ImGui::End();
			return;
		}

		// As a specific feature guaranteed by the library, after calling Begin() the last Item represent the title bar. So e.g. IsItemHovered() will return true when hovering the title bar.
		// Here we create a context menu only available from the title bar.
		if (ImGui::BeginPopupContextItem())
		{
			if (ImGui::MenuItem("Close Console"))
				*p_open = false;
			ImGui::EndPopup();
		}

		//ImGui::TextWrapped("This example implements a console with basic coloring, completion and history. A more elaborate implementation may want to store entries along with extra data such as timestamp, emitter, etc.");
		//ImGui::TextWrapped("Enter 'HELP' for help, press TAB to use text completion.");

		// TODO: display items starting from the bottom

		//if (ImGui::SmallButton("Add Dummy Text")) { MyAddLog("%d some text", Items.Size); MyAddLog("some more text"); MyAddLog("display very important message here!"); } ImGui::SameLine();
		//if (ImGui::SmallButton("Add Dummy Error")) { MyAddLog("[error] something went wrong"); } ImGui::SameLine();
		if (ImGui::SmallButton("Clear")) { ClearLog(); } ImGui::SameLine();
		bool copy_to_clipboard = ImGui::SmallButton("Copy");
		//static float t = 0.0f; if (ImGui::GetTime() - t > 0.02f) { t = ImGui::GetTime(); MyAddLog("Spam %f", t); }

		ImGui::Separator();

		// Options menu
		if (ImGui::BeginPopup("Options"))
		{
			ImGui::Checkbox("Auto-scroll", &AutoScroll);
			ImGui::EndPopup();
		}

		// Options, Filter
		if (ImGui::Button("Options"))
			ImGui::OpenPopup("Options");
		ImGui::SameLine();
		Filter.Draw("Filter (\"incl,-excl\") (\"error\")", 180);
		ImGui::Separator();

		const float footer_height_to_reserve = ImGui::GetStyle().ItemSpacing.y + ImGui::GetFrameHeightWithSpacing(); // 1 separator, 1 input text
		ImGui::BeginChild("ScrollingRegion", ImVec2(0, -footer_height_to_reserve), false, ImGuiWindowFlags_HorizontalScrollbar); // Leave room for 1 separator + 1 InputText
		if (ImGui::BeginPopupContextWindow())
		{
			if (ImGui::Selectable("Clear")) ClearLog();
			ImGui::EndPopup();
		}

		// Display every line as a separate entry so we can change their color or add custom widgets. If you only want raw text you can use ImGui::TextUnformatted(log.begin(), log.end());
		// NB- if you have thousands of entries this approach may be too inefficient and may require user-side clipping to only process visible items.
		// You can seek and display only the lines that are visible using the ImGuiListClipper helper, if your elements are evenly spaced and you have cheap random access to the elements.
		// To use the clipper we could replace the 'for (int i = 0; i < Items.Size; i++)' loop with:
		//     ImGuiListClipper clipper(Items.Size);
		//     while (clipper.Step())
		//         for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++)
		// However, note that you can not use this code as is if a filter is active because it breaks the 'cheap random-access' property. We would need random-access on the post-filtered list.
		// A typical application wanting coarse clipping and filtering may want to pre-compute an array of indices that passed the filtering test, recomputing this array when user changes the filter,
		// and appending newly elements as they are inserted. This is left as a task to the user until we can manage to improve this example code!
		// If your items are of variable size you may want to implement code similar to what ImGuiListClipper does. Or split your data into fixed height items to allow random-seeking into your list.
		ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(4, 1)); // Tighten spacing
		if (copy_to_clipboard)
			ImGui::LogToClipboard();
		for (int i = 0; i < Items.Size; i++)
		{
			const char* item = Items[i];
			if (!Filter.PassFilter(item))
				continue;

			// Normally you would store more information in your item (e.g. make Items[] an array of structure, store color/type etc.)
			bool pop_color = false;
			if (strstr(item, "[error]")) { ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.4f, 0.4f, 1.0f)); pop_color = true; }
			else if (strncmp(item, "# ", 2) == 0) { ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.8f, 0.6f, 1.0f)); pop_color = true; }
			ImGui::TextUnformatted(item);
			if (pop_color)
				ImGui::PopStyleColor();
		}
		if (copy_to_clipboard)
			ImGui::LogFinish();

		if (ScrollToBottom || (AutoScroll && ImGui::GetScrollY() >= ImGui::GetScrollMaxY()))
			ImGui::SetScrollHereY(1.0f);
		ScrollToBottom = false;

		ImGui::PopStyleVar();
		ImGui::EndChild();
		ImGui::Separator();

		// Command-line
		bool reclaim_focus = false;
		if (ImGui::InputText("Input", InputBuf, IM_ARRAYSIZE(InputBuf), ImGuiInputTextFlags_EnterReturnsTrue | ImGuiInputTextFlags_CallbackCompletion | ImGuiInputTextFlags_CallbackHistory, &TextEditCallbackStub, (void*)this))
		{
			char* s = InputBuf;
			Strtrim(s);
			if (s[0])
				ExecCommand(s);
			strcpy(s, "");
			reclaim_focus = true;
		}

		// Auto-focus on window apparition
		ImGui::SetItemDefaultFocus();
		if (reclaim_focus)
			ImGui::SetKeyboardFocusHere(-1); // Auto focus previous widget

		ImGui::End();
	}

	void    ExecCommand(const char* command_line)
	{
		MyAddLog("# %s\n", command_line);

		// Insert into history. First find match and delete it so it can be pushed to the back. This isn't trying to be smart or optimal.
		HistoryPos = -1;
		for (int i = History.Size - 1; i >= 0; i--)
			if (Stricmp(History[i], command_line) == 0)
			{
				free(History[i]);
				History.erase(History.begin() + i);
				break;
			}
		History.push_back(Strdup(command_line));

		// Process command
		if (Stricmp(command_line, "CLEAR") == 0)
		{
			ClearLog();
		}
		else if (Stricmp(command_line, "HELP") == 0)
		{
			MyAddLog("Commands:");
			for (int i = 0; i < Commands.Size; i++)
				MyAddLog("- %s", Commands[i]);
		}
		else if (Stricmp(command_line, "HISTORY") == 0)
		{
			int first = History.Size - 10;
			for (int i = first > 0 ? first : 0; i < History.Size; i++)
				MyAddLog("%3d: %s\n", i, History[i]);
		}
		else
		{
			MyAddLog("Unknown command: '%s'\n", command_line);
		}

		// On commad input, we scroll to bottom even if AutoScroll==false
		ScrollToBottom = true;
	}

	static int TextEditCallbackStub(ImGuiInputTextCallbackData* data) // In C++11 you are better off using lambdas for this sort of forwarding callbacks
	{
		MyExampleAppConsole* console = (MyExampleAppConsole*)data->UserData;
		return console->TextEditCallback(data);
	}

	int     TextEditCallback(ImGuiInputTextCallbackData* data)
	{
		//MyAddLog("cursor: %d, selection: %d-%d", data->CursorPos, data->SelectionStart, data->SelectionEnd);
		switch (data->EventFlag)
		{
		case ImGuiInputTextFlags_CallbackCompletion:
		{
			// Example of TEXT COMPLETION

			// Locate beginning of current word
			const char* word_end = data->Buf + data->CursorPos;
			const char* word_start = word_end;
			while (word_start > data->Buf)
			{
				const char c = word_start[-1];
				if (c == ' ' || c == '\t' || c == ',' || c == ';')
					break;
				word_start--;
			}

			// Build a list of candidates
			ImVector<const char*> candidates;
			for (int i = 0; i < Commands.Size; i++)
				if (Strnicmp(Commands[i], word_start, (int)(word_end - word_start)) == 0)
					candidates.push_back(Commands[i]);

			if (candidates.Size == 0)
			{
				// No match
				MyAddLog("No match for \"%.*s\"!\n", (int)(word_end - word_start), word_start);
			}
			else if (candidates.Size == 1)
			{
				// Single match. Delete the beginning of the word and replace it entirely so we've got nice casing
				data->DeleteChars((int)(word_start - data->Buf), (int)(word_end - word_start));
				data->InsertChars(data->CursorPos, candidates[0]);
				data->InsertChars(data->CursorPos, " ");
			}
			else
			{
				// Multiple matches. Complete as much as we can, so inputing "C" will complete to "CL" and display "CLEAR" and "CLASSIFY"
				int match_len = (int)(word_end - word_start);
				for (;;)
				{
					int c = 0;
					bool all_candidates_matches = true;
					for (int i = 0; i < candidates.Size && all_candidates_matches; i++)
						if (i == 0)
							c = toupper(candidates[i][match_len]);
						else if (c == 0 || c != toupper(candidates[i][match_len]))
							all_candidates_matches = false;
					if (!all_candidates_matches)
						break;
					match_len++;
				}

				if (match_len > 0)
				{
					data->DeleteChars((int)(word_start - data->Buf), (int)(word_end - word_start));
					data->InsertChars(data->CursorPos, candidates[0], candidates[0] + match_len);
				}

				// List matches
				MyAddLog("Possible matches:\n");
				for (int i = 0; i < candidates.Size; i++)
					MyAddLog("- %s\n", candidates[i]);
			}

			break;
		}
		case ImGuiInputTextFlags_CallbackHistory:
		{
			// Example of HISTORY
			const int prev_history_pos = HistoryPos;
			if (data->EventKey == ImGuiKey_UpArrow)
			{
				if (HistoryPos == -1)
					HistoryPos = History.Size - 1;
				else if (HistoryPos > 0)
					HistoryPos--;
			}
			else if (data->EventKey == ImGuiKey_DownArrow)
			{
				if (HistoryPos != -1)
					if (++HistoryPos >= History.Size)
						HistoryPos = -1;
			}

			// A better implementation would preserve the data on the current input line along with cursor position.
			if (prev_history_pos != HistoryPos)
			{
				const char* history_str = (HistoryPos >= 0) ? History[HistoryPos] : "";
				data->DeleteChars(0, data->BufTextLen);
				data->InsertChars(0, history_str);
			}
		}
		}
		return 0;
	}
};

static void ShowMyExampleAppConsole(bool* p_open)
{
	static MyExampleAppConsole console;
	console.Draw("Debug Log", p_open);
}

uint32_t vdl_ctl;
uint32_t vdl_curr;
uint32_t vdl_prev;
uint32_t vdl_next;

uint32_t clut [32];

void process_logo() {
	/*
	clut[0x00] = 0x000000; clut[0x01] = 0x080808; clut[0x02] = 0x101010; clut[0x03] = 0x191919; clut[0x04] = 0x212121; clut[0x05] = 0x292929; clut[0x06] = 0x313131; clut[0x07] = 0x3A3A3A;
	clut[0x08] = 0x424242; clut[0x09] = 0x4A4A4A; clut[0x0A] = 0x525252; clut[0x0B] = 0x5A5A5A; clut[0x0C] = 0x636363; clut[0x0D] = 0x6B6B6B; clut[0x0E] = 0x737373; clut[0x0F] = 0x7B7B7B;
	clut[0x10] = 0x848484; clut[0x11] = 0x8C8C8C; clut[0x12] = 0x949494; clut[0x13] = 0x9C9C9C; clut[0x14] = 0xA5A5A5; clut[0x15] = 0xADADAD; clut[0x16] = 0xB5B5B5; clut[0x17] = 0xBDBDBD;
	clut[0x18] = 0xC5C5C5; clut[0x19] = 0xCECECE; clut[0x1A] = 0xD6D6D6; clut[0x1B] = 0xDEDEDE; clut[0x1C] = 0xE6E6E6; clut[0x1D] = 0xEFEFEF; clut[0x1E] = 0xF8F8F8; clut[0x1F] = 0xFFFFFF;
	*/

	uint32_t offset = top->rootp->core_3do__DOT__madam_inst__DOT__vdl_addr & 0xFFFFF;

	// Read the VDL / CLUT from vram_ptr...
	for (int i=0; i<=35; i++) {
		if (i==0) vdl_ctl = vram_ptr[ (offset>>2)+i ];
		else if (i==1) vdl_curr = vram_ptr[ (offset>>2)+i ];
		else if (i==2) vdl_prev = vram_ptr[ (offset>>2)+i ];
		else if (i==3) vdl_next = vram_ptr[ (offset>>2)+i ];
		else if (i>=4) clut[i-4] = vram_ptr[ (offset>>2)+i ];
	}

	// Copy the VRAM pixels into disp_ptr...
	// Just a dumb test atm. Assuming 16bpp from vram_ptr, with odd and even pixels in the upper/lower 16 bits.
	//
	// vram_ptr is 32-bit wide!
	// vram_size = 1MB, so needs to be divided by 4 if used as an index.
	//
	uint32_t my_line = 0;

	offset = 0xC0000;

	for (int i=0; i<(vram_size/16); i++) {
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

int verilate() {
	if (!Verilated::gotFinish()) {
		//while ( top->rootp->FL_ADDR < 0x0100 ) {		// Only run for a short time.
		if (main_time < 100) {
			top->reset_n = 0;   	// Assert reset (active LOW)
		}
		if (main_time == 100) {		// Do == here, so we can still reset it in the main loop.
			top->reset_n = 1;		// Deassert reset./
		}
		//if ((main_time & 1) == 1) {
		//top->rootp->sys_clk = 1;       // Toggle clock
		//}
		//if ((main_time & 1) == 0) {
		//top->rootp->sys_clk = 0;

		pix_count++;

		uint32_t temp_word;

		uint32_t word_addr = (top->o_wb_adr)>>2;

		// Handle writes to Main RAM, with byte masking...
		if (top->o_wb_adr>=0x00000000 && top->o_wb_adr<=0x001FFFFF && top->o_wb_stb && top->o_wb_we) {		// 2MB masked.
			//printf("Main RAM Write!  Addr:0x%08X  Data:0x%08X  BE:0x%01X\n", top->o_wb_adr&0xFFFFF, top->o_wb_dat, top->o_wb_sel);
			temp_word = ram_ptr[word_addr&0x7FFFF];
			if ( top->o_wb_sel&8 ) ram_ptr[word_addr&0x7FFFF] = temp_word&0x00FFFFFF | top->o_wb_dat&0xFF000000;	// MSB byte.
			temp_word = ram_ptr[word_addr&0x7FFFF];
			if ( top->o_wb_sel&4 ) ram_ptr[word_addr&0x7FFFF] = temp_word&0xFF00FFFF | top->o_wb_dat&0x00FF0000;
			temp_word = ram_ptr[word_addr&0x7FFFF];
			if ( top->o_wb_sel&2 ) ram_ptr[word_addr&0x7FFFF] = temp_word&0xFFFF00FF | top->o_wb_dat&0x0000FF00;
			temp_word = ram_ptr[word_addr&0x7FFFF];
			if ( top->o_wb_sel&1 ) ram_ptr[word_addr&0x7FFFF] = temp_word&0xFFFFFF00 | top->o_wb_dat&0x000000FF;	// LSB byte.
		}

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

		rom_byteswapped = (rom_ptr[word_addr&0x3FFFF]&0xFF000000)>>24 | 
			(rom_ptr[word_addr&0x3FFFF]&0x00FF0000)>>8 | 
			(rom_ptr[word_addr&0x3FFFF]&0x0000FF00)<<8 | 
			(rom_ptr[word_addr&0x3FFFF]&0x000000FF)<<24;

		rom2_byteswapped = (rom2_ptr[word_addr&0x3FFFF]&0xFF000000)>>24 | 
			(rom2_ptr[word_addr&0x3FFFF]&0x00FF0000)>>8 | 
			(rom2_ptr[word_addr&0x3FFFF]&0x0000FF00)<<8 | 
			(rom2_ptr[word_addr&0x3FFFF]&0x000000FF)<<24;

		/*
		ram_byteswapped = (ram_ptr[word_addr&0x7FFFF]&0xFF000000)>>24 | 
		(ram_ptr[word_addr&0x7FFFF]&0x00FF0000)>>8 | 
		(ram_ptr[word_addr&0x7FFFF]&0x0000FF00)<<8 | 
		(ram_ptr[word_addr&0x7FFFF]&0x000000FF)<<24;
		*/

		//cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__fetch_pc_ff;
		cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__fifo_pc_plus_8;

		//trace = 1;

		if (top->i_wb_ack) next_ack = 0;
		top->i_wb_ack = next_ack;

		if (top->o_wb_stb) {
			next_ack = 1;
			//if (cur_pc==0x03000EF4) trace = 1;

			if (trace) {
				//if ((cur_pc>(old_pc+8)) || (cur_pc<(old_pc-8))) {
				if (cur_pc!=old_pc) {
					fprintf(logfile, "PC: 0x%08X \n", cur_pc);
					old_pc = cur_pc;
				}
			}

			/*
			uint32_t rom_test = (rom_ptr[top->rootp->core_3do__DOT__arm_pc & 0x3FFFF] & 0xFF000000) >> 24 |
			(rom_ptr[top->rootp->core_3do__DOT__arm_pc & 0x3FFFF] & 0x00FF0000) >> 8 |
			(rom_ptr[top->rootp->core_3do__DOT__arm_pc & 0x3FFFF] & 0x0000FF00) << 8 |
			(rom_ptr[top->rootp->core_3do__DOT__arm_pc & 0x3FFFF] & 0x000000FF) << 24;

			top->rootp->core_3do__DOT__arm_inst = rom_test;
			*/

			//if (top->o_wb_adr==0x03400084) trace = 1;
			//if (trace) fprintf(logfile, "PC: 0x%08X \n", cur_pc);

			if (top->o_wb_adr >= 0x03100000 && top->o_wb_adr <= 0x034FFFFF /*&& !(top->o_wb_adr==0x03400044)*/) fprintf(logfile, "Addr: 0x%08X ", top->o_wb_adr);

			// Tech manual suggests "Any write to this area will unmap the BIOS".
			//if (top->o_wb_adr >= 0x00000000 && top->o_wb_dat <= 0x001FFFFF && top->o_wb_we) map_bios = 0;
			if (top->o_wb_adr>=0x00000000 && top->o_wb_dat<=0x00000000 && top->o_wb_we) map_bios = 0;

			// Main RAM reads...
			if (top->o_wb_adr >= 0x00000118 && top->o_wb_adr <= 0x00000118) top->i_wb_dat = 0xE3A00000;	// MOV R0, #0. Clear R0 ! TESTING! Skip big delay.
			//else if (top->o_wb_adr >= 0x00014f6c && top->o_wb_adr <= 0x00014f6f) top->i_wb_dat = 0xE1A00000;	// NOP ! SWI Overrun thing.
			//else if (top->o_wb_adr>=0x00000050 && top->o_wb_adr<=0x00000050) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) TESTING !
			//else if (top->o_wb_adr>=0x0000095C && top->o_wb_adr<=0x000009F0) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) TESTING !
			else if (top->o_wb_adr >= 0x00000000 && top->o_wb_adr <= 0x001FFFFF) {
				if (map_bios && rom_select == 0) top->i_wb_dat = rom_byteswapped;
				else if (map_bios && rom_select == 1) top->i_wb_dat = rom2_byteswapped;
				else { top->i_wb_dat = ram_ptr[word_addr & 0x7FFFF]; }
			}

			else if (top->o_wb_adr >= 0x00200000 && top->o_wb_adr <= 0x002FFFFF) { /*fprintf(logfile, "VRAM            ");*/ top->i_wb_dat = vram_ptr[word_addr & 0x3FFFF]; /*if (top->o_wb_we) vram_ptr[word_addr&0x7FFFF] = top->o_wb_dat;*/ }

			// BIOS reads...
			//else if (top->o_wb_adr>=0x03000218 && top->o_wb_adr<=0x03000220) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip t2_testmemory and BeepsAndHold. TESTING!

			else if (top->o_wb_adr >= 0x03000510 && top->o_wb_adr <= 0x03000510) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip another delay.
			else if (top->o_wb_adr >= 0x03000504 && top->o_wb_adr <= 0x0300050C) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip another delay.
			//else if (top->o_wb_adr>=0x03000340 && top->o_wb_adr<=0x03000340) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip endless loop on mem size check fail.
			else if (top->o_wb_adr >= 0x030006a8 && top->o_wb_adr <= 0x030006b0) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0) Skip test_vram_svf. TESTING !!
			//else if (top->o_wb_adr>=0x030008E0 && top->o_wb_adr<=0x03000944) top->i_wb_dat = 0xE1A00000;	// NOP ! (MOV R0,R0)
			//else if (top->o_wb_adr>=0x0300056C && top->o_wb_adr<=0x0300056C) top->i_wb_dat = 0xE888001F;	// STM fix. TESTING !!
			else if (top->o_wb_adr >= 0x03000000 && top->o_wb_adr <= 0x030FFFFF) { /*fprintf(logfile, "BIOS            ");*/ top->i_wb_dat = rom_byteswapped; }

			else if (top->o_wb_adr >= 0x03100000 && top->o_wb_adr <= 0x03100020) { fprintf(logfile, "Brooktree       "); top->i_wb_dat = 0xBADACCE5; }
			//else if (top->o_wb_adr>=0x03100000 && top->o_wb_adr<=0x0313FFFF) { fprintf(logfile, "Brooktree       "); top->i_wb_dat = 0x0000006A; /*line_count = 0; vcnt_max=262;*/ }	// Spoof the first read value.

			else if (top->o_wb_adr >= 0x03140000 && top->o_wb_adr <= 0x0315FFFF) { fprintf(logfile, "NVRAM           "); }
			else if (top->o_wb_adr == 0x03180000 && top->o_wb_we) { fprintf(logfile, "DiagPort        "); shift_reg = 0x2000; }
			else if (top->o_wb_adr == 0x03180000 && !top->o_wb_we) { fprintf(logfile, "DiagPort        "); top->i_wb_dat = 0x00000000; }
			//else if (top->o_wb_adr==0x03180000 && !top->o_wb_we) { fprintf(logfile, "DiagPort        "); top->i_wb_dat = (shift_reg&0x8000)>>15; shift_reg=shift_reg<<1; }
			else if (top->o_wb_adr >= 0x03180004 && top->o_wb_adr <= 0x031BFFFF) { fprintf(logfile, "Slow Bus        "); }
			else if (top->o_wb_adr >= 0x03200000 && top->o_wb_adr <= 0x0320FFFF) { fprintf(logfile, "VRAM SVF        "); top->i_wb_dat = 0xBADACCE5; }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x032F0000 && top->o_wb_adr <= 0x032FFFFF) { fprintf(logfile, "Unknown         "); top->i_wb_dat = 0xBADACCE5; }	// Dummy reads for now.

			// MADAM...
			else if (top->o_wb_adr == 0x03300000 && !top->o_wb_we) { fprintf(logfile, "MADAM Revision  "); /*top->i_wb_dat = 0x01020000;*/ }
			else if (top->o_wb_adr == 0x03300000 && top->o_wb_we) { fprintf(logfile, "MADAM Print     "); MyAddLog("%c", top->o_wb_dat & 0xff); printf("%c", top->o_wb_dat & 0xff); }

			else if (top->o_wb_adr == 0x03300004 && top->o_wb_we) { fprintf(logfile, "MADAM msysbits  "); /*msys_reg = top->o_wb_dat;*/ }
			//else if (top->o_wb_adr==0x03300004 && !top->o_wb_we) { fprintf(logfile, "MADAM msysbits  "); top->i_wb_dat = msys_reg; }
			else if (top->o_wb_adr == 0x03300004 && !top->o_wb_we) { fprintf(logfile, "MADAM msysbits  "); /*top->i_wb_dat = 0x00000029;*/ }

			else if (top->o_wb_adr == 0x03300008 && top->o_wb_we) { fprintf(logfile, "MADAM mctl      "); /*mctl_reg = top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03300008 && !top->o_wb_we) { fprintf(logfile, "MADAM mctl      "); /*top->i_wb_dat = mctl_reg;*/ }
			else if (top->o_wb_adr == 0x0330000C && top->o_wb_we) { fprintf(logfile, "MADAM sltime    "); /*sltime_reg = top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x0330000C && !top->o_wb_we) { fprintf(logfile, "MADAM sltime    "); /*top->i_wb_dat = sltime_reg;*/ }
			else if (top->o_wb_adr == 0x03300020 && !top->o_wb_we) { fprintf(logfile, "MADAM abortbits "); /*top->i_wb_dat = abortbits;*/ }
			else if (top->o_wb_adr == 0x03300020 && top->o_wb_we) { fprintf(logfile, "MADAM abortbits "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03300574 && !top->o_wb_we) { fprintf(logfile, "MADAM PBUS thing"); /*top->i_wb_dat = 0xFFFFFFFC;*/ }
			else if (top->o_wb_adr == 0x03300580 && top->o_wb_we) { fprintf(logfile, "MADAM vdl_addr! "); /*vdl_addr_reg = top->o_wb_dat;*/ }
			else if (top->o_wb_adr >= 0x03300000 && top->o_wb_adr <= 0x033FFFFF) { fprintf(logfile, "MADAM           "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads.

			// CLIO...
			else if (top->o_wb_adr == 0x03400000 && !top->o_wb_we) { fprintf(logfile, "CLIO Revision   "); /*top->i_wb_dat = 0x02020000;*/ }
			else if (top->o_wb_adr == 0x03400004 && top->o_wb_we) { fprintf(logfile, "CLIO vint0      "); /*vint0_reg = top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03400004 && !top->o_wb_we) { fprintf(logfile, "CLIO vint0      "); /*top->i_wb_dat = vint0_reg;*/ }
			else if (top->o_wb_adr == 0x0340000C && top->o_wb_we) { fprintf(logfile, "CLIO vint1      "); /*vint1_reg = top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x0340000C && !top->o_wb_we) { fprintf(logfile, "CLIO vint1      "); /*top->i_wb_dat = vint1_reg;*/ }

			else if (top->o_wb_adr == 0x03400024) { fprintf(logfile, "CLIO audout     "); /*top->i_wb_dat = 0;*/ }

			else if (top->o_wb_adr == 0x03400028 && top->o_wb_we) { fprintf(logfile, "CLIO cstatbits  "); /*cstat_reg = top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03400028 && !top->o_wb_we) { fprintf(logfile, "CLIO cstatbits  "); /*top->i_wb_dat = cstat_reg;*/ }	// bit 6 = ? bit 0 = Reset of CLIO caused by power-on.
			else if (top->o_wb_adr == 0x03400034 && top->o_wb_we) { fprintf(logfile, "CLIO vcnt       "); /*clio_vcnt = top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03400034 && !top->o_wb_we) { fprintf(logfile, "CLIO vcnt       "); /*top->i_wb_dat = (field<<11) | line_count;*/ }

			else if (top->o_wb_adr == 0x03400040 && top->o_wb_we) { fprintf(logfile, "CLIO irq0 set   "); /*irq0 |= top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03400044 && top->o_wb_we) { fprintf(logfile, "CLIO irq0 clear "); /*irq0 &= ~top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03400048 && top->o_wb_we) { fprintf(logfile, "CLIO mask0 set  "); /*mask0 |= top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x0340004c && top->o_wb_we) { fprintf(logfile, "CLIO mask0 clear"); /*mask0 &= ~top->o_wb_dat;*/ }

			else if (top->o_wb_adr == 0x03400060 && top->o_wb_we) { fprintf(logfile, "CLIO irq1 set   "); /*irq1 |= top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03400064 && top->o_wb_we) { fprintf(logfile, "CLIO irq1 clear "); /*irq1 &= ~top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x03400068 && top->o_wb_we) { fprintf(logfile, "CLIO mask1 set  "); /*mask1 |= top->o_wb_dat;*/ }
			else if (top->o_wb_adr == 0x0340006c && top->o_wb_we) { fprintf(logfile, "CLIO mask1 clear"); /*mask1 &= ~top->o_wb_dat;*/ }

			else if (top->o_wb_adr >= 0x03400040 && top->o_wb_adr <= 0x03400044 && !top->o_wb_we) { fprintf(logfile, "CLIO irq0 read   "); /*top->i_wb_dat = irq0;*/ }
			else if (top->o_wb_adr >= 0x03400048 && top->o_wb_adr <= 0x0340004C && !top->o_wb_we) { fprintf(logfile, "CLIO mask0 read  "); /*top->i_wb_dat = mask0;*/ }

			else if (top->o_wb_adr >= 0x03400060 && top->o_wb_adr <= 0x03400064 && !top->o_wb_we) { fprintf(logfile, "CLIO irq1 read   "); /*top->i_wb_dat = irq1;*/ }
			else if (top->o_wb_adr >= 0x03400068 && top->o_wb_adr <= 0x0340006C && !top->o_wb_we) { fprintf(logfile, "CLIO mask1 read  "); /*top->i_wb_dat = mask1;*/ }

			else if (top->o_wb_adr == 0x03400080) { fprintf(logfile, "CLIO hdelay     "); /*top->i_wb_dat = 0;*/ }
			else if (top->o_wb_adr == 0x03400084 && !top->o_wb_we) { fprintf(logfile, "CLIO adbio      "); /*top->i_wb_dat = 0;*/ }
			else if (top->o_wb_adr == 0x03400084 && top->o_wb_we) { fprintf(logfile, "CLIO adbio      "); rom_select = (top->o_wb_dat & 0x40); }
			else if (top->o_wb_adr == 0x03400088) { fprintf(logfile, "CLIO adbctl     "); /*top->i_wb_dat = 0;*/ }
			else if (top->o_wb_adr >= 0x03400100 && top->o_wb_adr <= 0x0340017F && !(top->o_wb_adr & 4)) { fprintf(logfile, "CLIO timer_cnt  "); /*top->i_wb_dat = 0x00000040;*/ }
			else if (top->o_wb_adr >= 0x03400100 && top->o_wb_adr <= 0x0340017F && (top->o_wb_adr & 4)) { fprintf(logfile, "CLIO timer_bkp  "); /*top->i_wb_dat = 0x00000040;*/ }
			else if (top->o_wb_adr == 0x03400200) { fprintf(logfile, "CLIO timer1_set "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400204) { fprintf(logfile, "CLIO timer1_clr "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400208) { fprintf(logfile, "CLIO timer2_set "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x0340020C) { fprintf(logfile, "CLIO timer2_clr "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400220) { fprintf(logfile, "CLIO slack      "); /*top->i_wb_dat = 0x00000040;*/ }
			else if (top->o_wb_adr == 0x03400304) { fprintf(logfile, "CLIO dma        "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400308) { fprintf(logfile, "CLIO dmareqdis  "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400400) { fprintf(logfile, "CLIO expctl_set "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400404) { fprintf(logfile, "CLIO expctl_clr "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400408) { fprintf(logfile, "CLIO type0_4    "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400410) { fprintf(logfile, "CLIO dipir1     "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr == 0x03400414) { fprintf(logfile, "CLIO dipir2     "); /*top->i_wb_dat = 0x00004000;*/ }
			else if (top->o_wb_adr >= 0x03400500 && top->o_wb_adr <= 0x0340053f) { fprintf(logfile, "CLIO sel        "); /*top->i_wb_dat = 0x00000000;*/ }
			else if (top->o_wb_adr >= 0x03400540 && top->o_wb_adr <= 0x0340057f) { fprintf(logfile, "CLIO poll       "); /*top->i_wb_dat = 0x00000000;*/ }

			else if (top->o_wb_adr >= 0x034017d0 && top->o_wb_adr <= 0x034017d0) { fprintf(logfile, "CLIO sema       "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034017d4 && top->o_wb_adr <= 0x034017d4) { fprintf(logfile, "CLIO semaack    "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034017e0 && top->o_wb_adr <= 0x034017e0) { fprintf(logfile, "CLIO dspdma     "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034017e4 && top->o_wb_adr <= 0x034017e4) { fprintf(logfile, "CLIO dspprst0   "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034017e8 && top->o_wb_adr <= 0x034017e8) { fprintf(logfile, "CLIO dspprst1   "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034017f4 && top->o_wb_adr <= 0x034017f4) { fprintf(logfile, "CLIO dspppc     "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034017f8 && top->o_wb_adr <= 0x034017f8) { fprintf(logfile, "CLIO dsppnr     "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034017fc && top->o_wb_adr <= 0x034017fc) { fprintf(logfile, "CLIO dsppgw     "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x034039dc && top->o_wb_adr <= 0x034039dc) { fprintf(logfile, "CLIO dsppclkreload"); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.

			else if (top->o_wb_adr >= 0x03401800 && top->o_wb_adr <= 0x03401fff) { fprintf(logfile, "CLIO DSPP  N 32 "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x03402000 && top->o_wb_adr <= 0x03402fff) { fprintf(logfile, "CLIO DSPP  N 16 "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x03403000 && top->o_wb_adr <= 0x034031ff) { fprintf(logfile, "CLIO DSPP EI 32 "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x03403400 && top->o_wb_adr <= 0x034037ff) { fprintf(logfile, "CLIO DSPP EI 16 "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x0340C000 && top->o_wb_adr <= 0x0340C000) { fprintf(logfile, "CLIO unc_rev    "); /*top->i_wb_dat = 0x03800000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x0340C000 && top->o_wb_adr <= 0x0340C004) { fprintf(logfile, "CLIO unc_soft_rv"); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x0340C000 && top->o_wb_adr <= 0x0340C008) { fprintf(logfile, "CLIO unc_addr   "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x0340C000 && top->o_wb_adr <= 0x0340C00C) { fprintf(logfile, "CLIO unc_rom    "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else if (top->o_wb_adr >= 0x03400000 && top->o_wb_adr <= 0x034FFFFF) { fprintf(logfile, "CLIO            "); /*top->i_wb_dat = 0x00000000;*/ }	// Dummy reads for now.
			else /*top->i_wb_dat = 0xBADACCE5*/;	// Dummy reads for now.

			//if (top->o_wb_sel != 0xF) fprintf(logfile, "BYTE! ");

			madam_cs = (top->o_wb_adr >= 0x03300000 && top->o_wb_adr <= 0x0330FFFF);
			clio_cs = (top->o_wb_adr >= 0x03400000 && top->o_wb_adr <= 0x0340FFFF);
			svf_cs = (top->o_wb_adr == 0x03206100 || top->o_wb_adr == 0x03206900);
			svf2_cs = (top->o_wb_adr == 0x032002B4);

			uint32_t read_data = (madam_cs) ? top->rootp->core_3do__DOT__madam_dout :
				(clio_cs) ? top->rootp->core_3do__DOT__clio_dout :
				(svf_cs) ? 0xBADACCE5 :
				(svf2_cs) ? 0x00000000 :
				top->i_wb_dat;	// Else, take input from the C code in the sim. (TESTING, for BIOS, DRAM, VRAM, NVRAM etc.)

			if (top->o_wb_adr >= 0x03100000 && top->o_wb_adr <= 0x034FFFFF /*&& !(top->o_wb_adr==0x03400044)*/) {
				//if (top->o_wb_we) fprintf(logfile, "Write: 0x%08X  (PC: 0x%08X)  o_wb_sel: 0x%01X  o_wb_bte: 0x%01X\n", top->i_wb_dat, cur_pc, top->o_wb_sel, top->o_wb_bte);
				if (top->o_wb_we) fprintf(logfile, "Write: 0x%08X  (PC: 0x%08X)\n", top->o_wb_dat, cur_pc);	// Disabling BE bit printf for now. (sync with Opera).
				//else fprintf(logfile, " Read: 0x%08X  (PC: 0x%08X)\n", top->rootp->core_3do__DOT__zap_top_inst__DOT__i_wb_dat, cur_pc);
				else fprintf(logfile, " Read: 0x%08X  (PC: 0x%08X)\n", read_data, cur_pc);
			}

			/*
			if (GENERATE_JSON && top->sys_clk && (madam_cs || clio_cs || svf_cs || svf2_cs) && top->o_wb_cti!=7) {
			waveDrom["clock"].add(top->sys_clk);
			waveDrom["o_wb_adr"].add(top->o_wb_adr);
			waveDrom["i_wb_dat"].add(top->i_wb_dat);
			waveDrom["o_wb_dat"].add(top->o_wb_dat);
			waveDrom["o_wb_stb"].add(top->o_wb_stb);
			waveDrom["i_wb_ack"].add(top->i_wb_ack);
			waveDrom["write"].add(top->o_wb_we);
			}
			*/

			if (GENERATE_JSON && top->reset_n) {
				waveDrom["clock"].add(top->sys_clk);
				waveDrom["o_wb_adr"].add(top->o_wb_adr);
				waveDrom["i_wb_dat"].add(top->i_wb_dat);
				waveDrom["o_wb_dat"].add(top->o_wb_dat);
				waveDrom["o_wb_stb"].add(top->o_wb_stb);
				waveDrom["i_wb_ack"].add(top->i_wb_ack);
				waveDrom["write"].add(top->o_wb_we);
			}

			/*
			bool is_bios = top->o_wb_adr>=0x03000000 && top->o_wb_adr<=0x030FFFFF;
			bool is_ram  = top->o_wb_adr>=0x00000000 && top->o_wb_adr<=0x001FFFFF;
			if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x0A ) printf("Addr: 0x%08X BEQ!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x1A ) printf("Addr: 0x%08X BNE!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x2A ) printf("Addr: 0x%08X BCS!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x3A ) printf("Addr: 0x%08X BCC!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x4A ) printf("Addr: 0x%08X BMI!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x5A ) printf("Addr: 0x%08X BPL!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x6A ) printf("Addr: 0x%08X BVS!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x7A ) printf("Addr: 0x%08X BVC!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x8A ) printf("Addr: 0x%08X BHI!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0x9A ) printf("Addr: 0x%08X BLS!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0xAA ) printf("Addr: 0x%08X BGE!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0xBA ) printf("Addr: 0x%08X BLT!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0xCA ) printf("Addr: 0x%08X BGT!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0xDA ) printf("Addr: 0x%08X BLE!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0xEA ) printf("Addr: 0x%08X BAL!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && (top->i_wb_dat>>24)==0xEB ) printf("Addr: 0x%08X BL !  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			else if ( (is_bios | is_ram) && !top->o_wb_we && top->i_wb_dat==0xE1A0F00E ) printf("Addr: 0x%08X RET!  i_wb_dat: 0x%08X\n", top->o_wb_adr, top->i_wb_dat);
			*/

		}	//PC: 0x%08X\n", top->o_wb_adr, top->i_wb_dat, top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__decode_pc_ff);

			/*
			if (top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__ubyte) {
			top->i_wb_dat = (top->i_wb_dat&0xFF000000)>>24 | 
			(top->i_wb_dat&0x00FF0000)>>8 | 
			(top->i_wb_dat&0x0000FF00)<<8 | 
			(top->i_wb_dat&0x000000FF)<<24;
			}
			*/

			//cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__decode_pc_ff;
			//cur_pc = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__predecode_pc;		// Seems to match more closely to the real PC, but still jumping around?

			/*
			if (old_pc != cur_pc) {
			//printf("PC=0x%08X  ", cur_pc);
			//printf("R15: 0x%08X \n", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__i_pc_ff);
			printf("PC: 0x%08X  o_wb_adr: 0x%08X\n", cur_pc, top->o_wb_adr);
			}
			old_pc = cur_pc;
			*/

			/*
			if (old_pc != cur_pc) {
			printf("PC: 0x%08X  i_wb_dat: 0x%08X\n", cur_pc, top->i_wb_dat);
			printf("R0: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r0);
			printf("R1: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r1);
			printf("R2: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r2);
			printf("R3: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r3);
			printf("R4: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r4);
			printf("R5: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r5);
			printf("R6: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r6);
			printf("R7: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r7);
			printf("R8: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r8);
			printf("R9: 0x%08X ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r9);
			printf("R10: 0x%08X \n\n", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r10);
			}
			old_pc = cur_pc;
			*/

		if (top->rootp->core_3do__DOT__clio_inst__DOT__vcnt==top->rootp->core_3do__DOT__clio_inst__DOT__vcnt_max && top->rootp->core_3do__DOT__clio_inst__DOT__hcnt==0) {
			frame_count++;
			process_logo();
		}

		/*
		if (line_count==vcnt_max) {
		line_count=0;
		field = !field;
		frame_count++;
		process_logo();
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
		//}

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

	if (GENERATE_JSON) {
		waveDrom.add(WaveDromSignal("clock"));
		waveDrom.add(WaveDromSignal("o_wb_adr", true));
		waveDrom.add(WaveDromSignal("i_wb_dat", true));
		waveDrom.add(WaveDromSignal("o_wb_dat", true));
		waveDrom.add(WaveDromSignal("o_wb_stb"));
		waveDrom.add(WaveDromSignal("i_wb_ack"));
		waveDrom.add(WaveDromSignal("write"));
	}

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
			trig_irq = 0;
			trig_fiq = 0;
			field = 1;
			frame_count = 0;
			line_count = 0;
			//vcnt_max = 262;
			memset(disp_ptr, 0xff444444, disp_size);	// Clear the DISPLAY buffer.
			memset(ram_ptr, 0x00000000, ram_size);		// Clear Main RAM.
			memset(vram_ptr, 0x00000000, vram_size);	// Clear VRAM.
		}
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

		//bool irq_button_pressed = ImGui::Button("Tickle IRQ");
		//if (trig_irq==0 && irq_button_pressed) trig_irq = 1;

		//bool firq_button_pressed = ImGui::Button("Tickle FIRQ");
		//if (trig_fiq==0 && firq_button_pressed) trig_fiq = 1;

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

		ImGui::Begin("ARM Registers");

		ImGui::Text("     reset_n: %d", top->rootp->core_3do__DOT__reset_n);
		ImGui::Separator();

		//if ( (top->rootp->o_wb_cti!=7) || (top->rootp->o_wb_bte!=0) ) { run_enable=0; printf("cti / bte changed!!\n"); }

		if (run_enable) for (int step = 0; step < 2048; step++) {	// Simulates MUCH faster if it's done in batches.
			verilate();

			//if (top->rootp->o_wb_adr>=0x03400100 && top->rootp->o_wb_adr<=0x03400180 && top->rootp->o_wb_we && top->rootp->o_wb_stb) { run_enable=0; break; }	// Stop on CLIO timer access.

			//Is this a folio we are pointing to now?
			//teq	r9,#0
			//beq	aborttask

			//if (cur_pc==0x0001162c) { run_enable=0; second_stop=1; break; }

			if (cur_pc==0x00010460) { run_enable=0; second_stop=1; break; }

			//if (cur_pc==0x00011624) { run_enable=0; second_stop=1; break; }
			//if (second_stop && top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r9==0) { run_enable=0; break; }

			//if (top->rootp->core_3do__DOT__zap_top_inst__DOT__i_fiq) { run_enable=0; break; }

			//if (cur_pc==0x000002b8) { run_enable=0; break; }

			//if (top->rootp->o_wb_adr==0x03300580) { run_enable=0; break; }

			//if (top->rootp->core_3do__DOT__clio_inst__DOT__irq1_enable&0x100) { run_enable=0; break; }

			//if (top->rootp->o_wb_adr==0x00200000 && top->rootp->o_wb_we && top->rootp->o_wb_stb) { run_enable=0; break; }	// TESTING - Stop sim on first VRAM access.

			//if (top->rootp->o_wb_adr==0x032FFFEC) { run_enable = 0; break; }
			//if (top->rootp->o_wb_adr==0x00000114 && top->rootp->o_wb_stb && !top->rootp->o_wb_we) { run_enable = 0; break; }
			//if (top->rootp->o_wb_adr==0x00000038 && !top->rootp->o_wb_we) { run_enable = 0; break; }
			//if (top->rootp->o_wb_adr==0x00000050 && !top->rootp->o_wb_we) { run_enable = 0; break; }
			//if (top->rootp->o_wb_adr==0x00001600 && !top->rootp->o_wb_we) { run_enable = 0; break; }
			//if (top->rootp->o_wb_adr==0x00100000 && top->rootp->o_wb_we) { run_enable = 0; break; }
			//if (top->rootp->o_wb_adr==0x0000175C && top->rootp->o_wb_we) { run_enable = 0; break; }
			//if (top->rootp->o_wb_adr==0x03000338) { run_enable = 0; break; }
			//if (cur_pc==0x03000330) { run_enable = 0; break; }
			//if (cur_pc==0x00000178) { run_enable = 0; break; }
			//if (cur_pc==0x00000120) { run_enable = 0; break; }
			//if (top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_writeback__DOT__u_zap_register_file__DOT__r1==0x000019b1) { run_enable = 0; break; }

			//if (top->rootp->o_wb_adr>=0x1C && top->rootp->o_wb_adr<=0x1F && top->rootp->o_wb_we) { run_enable = 0; break; }	// Stop on writes to FIQ vector.

			//if (cur_pc==0x0000003c) { run_enable = 0; break; }
			//if (cur_pc==0x00000050) { run_enable = 0; break; }
			//if (cur_pc==0x030002C4) { run_enable = 0; break; }
			//if (cur_pc==0x00000960) { run_enable = 0; break; }
			//if (cur_pc==0x03000EB8) { run_enable = 0; break; }

			//if (top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__ubyte) { run_enable = 0; break; }
		}
		else {																// But, it will affect the update rate of the GUI.
			if (single_step) verilate();
			if (multi_step) for (int step = 0; step < multi_step_amount; step++) verilate();
		}

		if (top->rootp->o_wb_adr>=0x00000000 && top->rootp->o_wb_adr<=0x001FFFFF) { if (map_bios) ImGui::Text("    BIOS (mapped)"); else ImGui::Text("    Main RAM    "); }
		else if (top->rootp->o_wb_adr>=0x00200000 && top->rootp->o_wb_adr<=0x003FFFFF) ImGui::Text("       VRAM      ");
		else if (top->rootp->o_wb_adr>=0x03000000 && top->rootp->o_wb_adr<=0x030FFFFF) ImGui::Text("       BIOS      ");
		else if (top->rootp->o_wb_adr>=0x03100000 && top->rootp->o_wb_adr<=0x0313FFFF) ImGui::Text("       Brooktree ");
		else if (top->rootp->o_wb_adr>=0x03140000 && top->rootp->o_wb_adr<=0x0315FFFF) ImGui::Text("       NVRAM     ");
		else if (top->rootp->o_wb_adr==0x03180000) ImGui::Text("       DiagPort  ");
		else if (top->rootp->o_wb_adr>=0x03180004 && top->rootp->o_wb_adr<=0x031BFFFF) ImGui::Text("    Slow Bus     ");
		else if (top->rootp->o_wb_adr>=0x03200000 && top->rootp->o_wb_adr<=0x0320FFFF) ImGui::Text("       VRAM SVF  ");
		else if (top->rootp->o_wb_adr>=0x03300000 && top->rootp->o_wb_adr<=0x033FFFFF) ImGui::Text("       MADAM     ");
		else if (top->rootp->o_wb_adr>=0x03400000 && top->rootp->o_wb_adr<=0x034FFFFF) ImGui::Text("       CLIO      ");
		else ImGui::Text("    Unknown    ");

		//ImGui::Text("          PC: 0x%08X", top->rootp->core_3do__DOT__a23_core_inst__DOT__u_execute__DOT__u_register_bank__DOT__o_pc);
		ImGui::Text("    o_wb_adr: 0x%08X", top->o_wb_adr);
		ImGui::Text("    i_wb_dat: 0x%08X", top->i_wb_dat);
		ImGui::Separator();
		ImGui::Text("    o_wb_dat: 0x%08X", top->o_wb_dat);
		ImGui::Text("     o_wb_we: %d", top->o_wb_we); ImGui::SameLine(); if (!top->rootp->o_wb_we) ImGui::Text(" Read"); else ImGui::Text(" Write");
		ImGui::Text("    o_wb_sel: 0x%01X", top->o_wb_sel);
		ImGui::Text("    o_wb_cyc: %d", top->o_wb_cyc);
		ImGui::Text("    o_wb_stb: %d", top->o_wb_stb);
		ImGui::Text("    i_wb_ack: %d", top->i_wb_ack);
		ImGui::Separator();
		ImGui::Text("       i_fiq: %d", top->rootp->core_3do__DOT__zap_top_inst__DOT__i_fiq); 
		ImGui::Separator();
		ImGui::Text("    Zap...");
		ImGui::Text("    o_wb_cti: 0x%01X", top->o_wb_cti);
		ImGui::Text("    o_wb_bte: 0x%01X", top->o_wb_bte);
		ImGui::Text("  i_mem_addr: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__i_mem_address_ff2);
		/*
		ImGui::Text("       sbyte: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__sbyte);
		ImGui::Text("       ubyte: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__ubyte);
		ImGui::Text("       shalf: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__shalf);
		ImGui::Text("       uhalf: %d", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__uhalf);
		ImGui::Text(" transform d: 0x%08X", top->rootp->__Vfunc_core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_memory_main__DOT__transform__114__transform_function__DOT__d);
		*/

		/*
		//ImGui::Text("  %s", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__i_decompile);
		for (int i=0; i<16; i++) {
		//uint32_t my_word = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__i_decompile[i];
		uint32_t my_word = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_decode_main__DOT__decompile_tmp[i];
		ImGui::Text("%c%c%c%c", (my_word>>24)&0xFF, (my_word>>16)&0xFF, (my_word>>8)&0xFF, (my_word>>0)&0xFF);
		ImGui::SameLine();
		}
		printf("\n");
		*/

		ImGui::Text("         op1: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__op1);
		ImGui::Text("         op2: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__op2);
		ImGui::Text("      opcode: 0x%01X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__u_zap_alu_main__DOT__opcode);

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
		ImGui::Text("reg_src: %d", reg_src);
		ImGui::Text("reg_dst: %d", reg_dst);
		ImGui::Separator();

		uint32_t cpsr = top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__o_cpsr;

		ImGui::Text("        CPSR: 0x%08X", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__o_cpsr);

		ImGui::Text("        bits: %d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d",
			(cpsr&0x80000000)>>31, (cpsr&0x40000000)>>30, (cpsr&0x20000000)>>29, (cpsr&0x10000000)>>28, (cpsr&0x08000000)>>27, (cpsr&0x04000000)>>26, (cpsr&0x02000000)>>25, (cpsr&0x01000000)>>24,
			(cpsr&0x00800000)>>23, (cpsr&0x00400000)>>22, (cpsr&0x00200000)>>21, (cpsr&0x00100000)>>20, (cpsr&0x00080000)>>19, (cpsr&0x00040000)>>18, (cpsr&0x00020000)>>17, (cpsr&0x00010000)>>16,
			(cpsr&0x00008000)>>15, (cpsr&0x00004000)>>14, (cpsr&0x00002000)>>13, (cpsr&0x00001000)>>12, (cpsr&0x00000800)>>11, (cpsr&0x00000400)>>10, (cpsr&0x00000200)>>9,  (cpsr&0x00000100)>>8,
			(cpsr&0x00000080)>>7,  (cpsr&0x00000040)>>6,  (cpsr&0x00000020)>>5,  (cpsr&0x00000010)>>4,  (cpsr&0x00000008)>>3,  (cpsr&0x00000004)>>2,  (cpsr&0x00000002)>>1,  (cpsr&0x00000001)>>0 );
		ImGui::Text("              NZCVQIIJ    GGGGIIIIIIEAIFTMMMMM", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__o_cpsr);
		ImGui::Text("                   TT     EEEETTTTTT          ", top->rootp->core_3do__DOT__zap_top_inst__DOT__u_zap_core__DOT__o_cpsr);
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
		ImGui::Text("timer_backup_10: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_10);	// 0x154
		ImGui::Text(" timer_count_11: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_11);		// 0x158
		ImGui::Text("timer_backup_11: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_11);	// 0x15c
		ImGui::Text(" timer_count_12: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_12);		// 0x160
		ImGui::Text("timer_backup_12: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_12);	// 0x164
		ImGui::Text(" timer_count_13: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_13);		// 0x168
		ImGui::Text("timer_backup_13: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_13);	// 0x16c
		ImGui::Text(" timer_count_14: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_14);		// 0x170
		ImGui::Text("timer_backup_14: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_14);	// 0x174
		ImGui::Text(" timer_count_15: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_count_15);		// 0x178
		ImGui::Text("timer_backup_15: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_backup_15);	// 0x17c
		ImGui::Separator();
		ImGui::Text("     timer_ctrl: 0x%016X", top->rootp->core_3do__DOT__clio_inst__DOT__timer_ctrl);		// 0x200,0x204,0x208,0x20c. 64-bits wide?? TODO: How to handle READS of the 64-bit reg?
		ImGui::End();

		ImGui::Begin("CLIO sel regs");
		ImGui::Text(" sel_0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_0);		// 0x500
		ImGui::Text(" sel_1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_1);		// 0x504
		ImGui::Text(" sel_2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_2);		// 0x508
		ImGui::Text(" sel_3: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_3);		// 0x50c
		ImGui::Text(" sel_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_4);		// 0x510
		ImGui::Text(" sel_5: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_5);		// 0x514
		ImGui::Text(" sel_6: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_6);		// 0x518
		ImGui::Text(" sel_7: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_7);		// 0x51c
		ImGui::Text(" sel_8: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_8);		// 0x520
		ImGui::Text(" sel_9: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_9);		// 0x524
		ImGui::Text("sel_10: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_10);		// 0x528
		ImGui::Text("sel_11: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_11);		// 0x52c
		ImGui::Text("sel_12: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_12);		// 0x530
		ImGui::Text("sel_13: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_13);		// 0x534
		ImGui::Text("sel_14: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_14);		// 0x538
		ImGui::Text("sel_15: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__sel_15);		// 0x53c
		ImGui::End();

		ImGui::Begin("CLIO poll regs");
		ImGui::Text(" poll_0: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_0);		// 0x540
		ImGui::Text(" poll_1: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_1);		// 0x544
		ImGui::Text(" poll_2: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_2);		// 0x548
		ImGui::Text(" poll_3: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_3);		// 0x54c
		ImGui::Text(" poll_4: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_4);		// 0x550
		ImGui::Text(" poll_5: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_5);		// 0x554
		ImGui::Text(" poll_6: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_6);		// 0x558
		ImGui::Text(" poll_7: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_7);		// 0x55c
		ImGui::Text(" poll_8: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_8);		// 0x560
		ImGui::Text(" poll_9: 0x%08X", top->rootp->core_3do__DOT__clio_inst__DOT__poll_9);		// 0x564
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

		/*
		ImGui::Begin("armsim");
		ImGui::Text("   pc: 0x%08X", top->rootp->core_3do__DOT__arm_pc);
		ImGui::Text(" inst: 0x%08X", top->rootp->core_3do__DOT__arm_inst);
		ImGui::End();
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

		//void ui_m6502_draw(ui_m6502_t* win);

		// 3. Show another simple window.
		/*
		if (show_another_window)
		{
		ImGui::Begin("Another Window", &show_another_window);   // Pass a pointer to our bool variable (the window will have a closing button that will clear the bool when clicked)
		ImGui::Text("Hello from another window!");
		if (ImGui::Button("Close Me"))
		show_another_window = false;
		ImGui::End();
		}
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


		//ram_ptr[0] = 0x00000000; // Don't remember what this is for??

		//my_dram = calloc(1, );
	}
	// Close imgui stuff properly...
	ImGui_ImplDX11_Shutdown();
	ImGui_ImplWin32_Shutdown();
	ImGui::DestroyContext();

	if (GENERATE_JSON) {
		waveDrom.write("out.json");
	}

	CleanupDeviceD3D();
	DestroyWindow(hwnd);
	UnregisterClass(wc.lpszClassName, wc.hInstance);

	return 0;
}
