//
//  ViceCityCheats.c
//  Stash
//
//  An ASI plugin for GTA: Vice City v1.0 (gta-vc.exe, 3,088,896 bytes) that adds two cheat codes,
//  typed during play like the game's own:
//
//    IMMORTAL  unlimited health and armour, and the car you're in can't be wrecked
//    NOCOPS    the police never chase you: your wanted level stays at zero
//
//  Typing a code again turns it off. The widescreen fix's ASI loader loads this from scripts/.
//  Build with StashCheats/build.sh.
//

#include <windows.h>
#include <string.h>
#include <wchar.h>

// Addresses in gta-vc.exe v1.0, checked against its code
#define CHEAT_KEY_CALL      0x602BC7    // call CPad::AddToPCCheatString, made once per key typed
#define ADD_TO_CHEAT_STRING 0x4ABD40
#define CHEAT_STRING        0xA1094A    // last 30 keys typed, newest first
#define SET_HELP_MESSAGE    0x55BFE0    // CHud::SetHelpMessage(text, quick, unused)
#define PLAYER_IN_FOCUS     0xA10B03
#define PLAYER_PEDS         0x94AD30    // CWorld::Players[i].m_pPed, 0x170 apart
#define PLAYER_MAX_HEALTH   0x94AE73
#define PLAYER_MAX_ARMOUR   0x94AE74
#define PLAYER_INFO_SIZE    0x170
#define PED_HEALTH          0x354
#define PED_ARMOUR          0x358
#define PED_VEHICLE         0x3A8
#define PED_IN_VEHICLE      0x3AC
#define VEHICLE_HEALTH      0x204
#define MAX_WANTED_LEVEL    0x6910D8    // CWanted::MaximumWantedLevel
#define MAX_CHAOS_LEVEL     0x6910DC    // CWanted::MaximumChaosLevel; wanted level follows chaos, capped by this

#define AT(type, address) (*(type volatile *)(address))

typedef void (__thiscall *AddToCheatStringFunction)(void *pad, char key);
typedef void (__cdecl *SetHelpMessageFunction)(const wchar_t *text, BOOL quick, BOOL unused);

static AddToCheatStringFunction addToCheatString;
static volatile LONG immortal, noCops;
static int savedMaxWanted, savedMaxChaos;

static int typed(const char *code) {
    const char *keys = (const char *)CHEAT_STRING;
    size_t length = strlen(code);
    for (size_t i = 0; i < length; i++) {
        char key = keys[i];
        if (key >= 'a' && key <= 'z') key -= 'a' - 'A';
        if (key != code[length - 1 - i]) return 0;
    }
    AT(char, CHEAT_STRING) = ' ';   // like the game: a code can't be completed twice by one key
    return 1;
}

static void announce(const wchar_t *text) {
    static wchar_t message[64];
    wcsncpy(message, text, 63);
    ((SetHelpMessageFunction)SET_HELP_MESSAGE)(message, TRUE, FALSE);
}

static void setNoCops(LONG on) {
    if (on) {
        savedMaxWanted = AT(int, MAX_WANTED_LEVEL);
        savedMaxChaos = AT(int, MAX_CHAOS_LEVEL);
    } else {
        AT(int, MAX_WANTED_LEVEL) = savedMaxWanted;
        AT(int, MAX_CHAOS_LEVEL) = savedMaxChaos;
    }
    InterlockedExchange(&noCops, on);
}

// Runs on the game's thread for every key typed during play
static void __fastcall onCheatKey(void *pad, void *unused, char key) {
    (void)unused;
    addToCheatString(pad, key);
    if (typed("IMMORTAL")) {
        InterlockedExchange(&immortal, !immortal);
        announce(immortal ? L"Unlimited health on" : L"Unlimited health off");
    } else if (typed("NOCOPS")) {
        setNoCops(!noCops);
        announce(noCops ? L"Police ignore you" : L"Police are back");
    }
}

static DWORD WINAPI keepEffects(LPVOID unused) {
    (void)unused;
    for (;;) {
        if (immortal) {
            unsigned focus = AT(unsigned char, PLAYER_IN_FOCUS);
            char *ped = AT(char *, PLAYER_PEDS + focus * PLAYER_INFO_SIZE);
            // A ped already at zero is dying; reviving it mid-death breaks the game's state
            if (ped && AT(float, ped + PED_HEALTH) > 0) {
                AT(float, ped + PED_HEALTH) = AT(unsigned char, PLAYER_MAX_HEALTH + focus * PLAYER_INFO_SIZE);
                AT(float, ped + PED_ARMOUR) = AT(unsigned char, PLAYER_MAX_ARMOUR + focus * PLAYER_INFO_SIZE);
                char *vehicle = AT(char *, ped + PED_VEHICLE);
                if (AT(char, ped + PED_IN_VEHICLE) && vehicle && AT(float, vehicle + VEHICLE_HEALTH) > 0)
                    AT(float, vehicle + VEHICLE_HEALTH) = 1000.0f;
            }
        }
        if (noCops) {
            // Missions raise the cap again, so it is held down continuously
            AT(int, MAX_WANTED_LEVEL) = 0;
            AT(int, MAX_CHAOS_LEVEL) = 0;
        }
        Sleep(5);
    }
    return 0;
}

static BOOL isViceCity10(void) {
    const unsigned char addToCheatStringStart[] = { 0x53, 0x56, 0x57, 0x55, 0x83, 0xEC, 0x10 };
    const unsigned char maxWantedCheck[] = { 0x3B, 0x05, 0xD8, 0x10, 0x69, 0x00 };   // cmp eax, [MaximumWantedLevel]
    // Every address used must be inside the loaded game before any is read
    unsigned char *image = (unsigned char *)GetModuleHandleA(NULL);
    IMAGE_NT_HEADERS *headers = (IMAGE_NT_HEADERS *)(image + ((IMAGE_DOS_HEADER *)image)->e_lfanew);
    if (image != (unsigned char *)0x400000 || headers->OptionalHeader.SizeOfImage <= CHEAT_STRING + 32 - 0x400000)
        return FALSE;
    return memcmp((void *)ADD_TO_CHEAT_STRING, addToCheatStringStart, sizeof addToCheatStringStart) == 0
        && memcmp((void *)0x4D1FC5, maxWantedCheck, sizeof maxWantedCheck) == 0
        && AT(unsigned char, CHEAT_KEY_CALL) == 0xE8;
}

static void install(void) {
    if (!isViceCity10()) {
        OutputDebugStringA("Stash cheats: not Vice City v1.0, cheats off\n");
        return;
    }
    // Keep whatever the call already goes to, in case another mod hooked it first
    unsigned char *call = (unsigned char *)CHEAT_KEY_CALL;
    addToCheatString = (AddToCheatStringFunction)(call + 5 + AT(LONG, call + 1));
    DWORD protection;
    if (!VirtualProtect(call, 5, PAGE_EXECUTE_READWRITE, &protection)) return;
    AT(LONG, call + 1) = (LONG)((unsigned char *)onCheatKey - (call + 5));
    VirtualProtect(call, 5, protection, &protection);
    FlushInstructionCache(GetCurrentProcess(), call, 5);
    CloseHandle(CreateThread(NULL, 0, keepEffects, NULL, 0, NULL));
    OutputDebugStringA("Stash cheats: ready\n");
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        install();
    }
    return TRUE;
}
