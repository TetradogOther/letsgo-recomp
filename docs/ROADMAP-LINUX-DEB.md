# Roteiro: port nativo para Linux e empacotamento `.deb` (Debian)

_23/10/2026. Documento de trabalho: o que ja foi validado neste repositorio, o que falta para o jogo rodar no
Debian e o que falta para o `.deb` estar pronto a publicar._

## 1. Onde estamos

O runtime ja e multi-plataforma: veio do [LAS Recomp](https://github.com/peiikai/LASRecomp), que tem um port Linux
pronto (`runtime/platform/linux.c`, tabelas HLE em secoes ELF, `__start_`/`__stop_`). O que **nao** existia neste
fork era o *empacotamento* e algumas correcoes que a janela "Windows" do fork deixou de lado.

**Validado nesta maquina (Debian 13 "trixie", x86-64, AMD Radeon 760M / RADV):**

| Verificacao | Resultado |
|---|---|
| `make runtime-objs` (PLATFORM=linux) | compila |
| `make` (link do runtime) | linka (`build/lasrecomp`, 7,7 MB) |
| Execuao | abre a janela **"Let's Go Recomp"** (774x900) e renderiza o launcher (icone, fonte Baloo2, paginas) |
| Vulkan | RADV 1.4.305 + lavapipe detectados; swapchain e aneis de memoria OK |
| `tools/linux/build_deb.sh` | gera `build/dist/letsgo-recomp_0.6.0_amd64.deb` (57 MB) |
| O `.deb` instalado | o binario de `/usr/bin` abre e renderiza (o icone vem de `/usr/share/letsgo-recomp/icon.png`) |
| O gerador (lasgen, PyInstaller) | corre no Linux (o `unicorn` e o `capstone` carregam) |
| O codigo do jogo | compilado com o `zig` do pacote e carregado pelo runtime (as tabelas das quatro modulos) |

O jogo em si **ainda nao foi testado**: exige os ficheiros proprios do utilizador (`exefs`/`romfs`) e o primeiro
"set up" compila ~920 ficheiros de codigo do jogo (zig/clang), como no Windows. **E o que falta para fechar o
rooteiro** (Fase 4).

## 2. Fase 0 — correcoes de portabilidade (feito)

O build Linux nao compilava. Estas correcoes ja estao aplicadas:

| # | Onde | Problema | Correcao |
|---|---|---|---|
| 0.1 | `runtime/platform/linux_compat.h` | `rmdir` sem declaracao (`runtime/mods.c`) | `#include <unistd.h>` |
| 0.2 | `runtime/paths.c`, `runtime/ui/launcher_lg.mm` | `SDL_LoadPNG` so existe no SDL3_image (nao esta no SDL3) | novo `runtime/png.c` (stb_image, ja vendorizado) → `rt_png_surface()` |
| 0.3 | `runtime/nvn/vulkan/device.c` | `SDL_SavePNG` (mesma origem) | `rt_png_write()` (stb_image_write) |
| 0.4 | `runtime/ui2x.c` | duas implementacoes do stb no mesmo link → simbolos duplicados | o stb passa a viver so em `runtime/png.c` |
| 0.5 | `runtime/hle/movie.c` | `stat`/`S_ISREG` sem `<sys/stat.h>` | include |
| 0.6 | `runtime/platform/linux.c` | `RT_APP_NAME` indefinido (falta `paths.h`) | include |
| 0.7 | `third_party/fidelityfx/.../ffx_api.h` | `__declspec` (MSVC) no header do FSR 3.1 | `__attribute__((visibility("default")))` fora do MSVC |
| 0.8 | `Makefile` | `-fuse-ld=lld` obrigatorio | `LD ?= lld` (usar `make LD=` num sistema sem lld) |
| 0.9 | `Makefile` | o SDL3 do Debian deixa `sio_*` (libudev) indefinidos e o linker recusa | `-Wl,--allow-shlib-undefined` |

**Nota de licenciamento:** as correcoes 0.2/0.3 removeram a dependencia do SDL3_image (que nem estava declarada no
Makefile do Windows) e passam a usar o `third_party/stb` ja vendorizado. Menos uma dependencia, mesmo codigo nas
duas plataformas.

## 3. Fase 1 — funcionalidade que era so-Windows

| # | Pri. | Situacao | Decisao |
|---|---|---|---|
| 1.1 | **P0** | **feito**: `runtime/platform.h` + `platform/{linux,windows}.c` gained `plat_unpack()` (bsdtar, or the system's tar; on Windows, the same `tar.exe`); `runtime/mods.c` no longer calls `C:\Windows\System32\tar.exe` | — |
| 1.2 | **P1** | **feito**: `runtime/ui2x.c` downloads the Linux release of the upscaler (sha256 checked) and unpacks it with `plat_unpack()` | — |
| 1.3 | **P1** | **parcial**: `vk_display_hz()` reads the display mode's refresh (SDL) → the frame generation's "Auto" follows the screen. The *vblank grid* (the compositor's timing, Windows' DWM) has no Linux equivalent yet: the interpolated images are not snapped to the refresh | measure the grid from the presents, or leave it off (the feature is experimental) |
| 1.4 | **P2** | **decidido**: FSR 3.1 stays Windows-only (the SDK's Linux build is not in the package); the log says so and the upscaler falls back to FSR 1. The in-house 2x/3x/4x and FSR 1 work | revisit if the AMD SDK's Linux build is worth the weight |
| 1.5 | **P1** | **decidido**: the package ships zig (as the Windows release does), so the player needs no compiler. `WITH_ZIG=0` builds a lighter package that depends on `clang` + `lld` | — |
| 1.6 | **P3** | the Switch's online services stay offline (as on Windows) | — |

## 4. Fase 2 — pipeline de build reproduzivel (feito)

| # | Tarefa | Estado |
|---|---|---|
| 2.1 | `tools/linux/Containerfile` | Debian 13 with the distribution's SDL3, FFmpeg, shaderc and Vulkan headers |
| 2.2 | `tools/linux/build_container.sh` | builds the package in the container (podman or docker) |
| 2.3 | o gerador congelado | `tools/lasgen.spec` ja e multi-plataforma (trata do `libunicorn.so.2`); o `build_deb.sh` monta-o com PyInstaller |
| 2.4 | zig | `tools/fetch_zig.sh` ja suporta Linux (sha256 fixado). O "slim" (`tools/zig_slim.sh`) e so do Windows: em Linux o primeiro link demora ~13 s e o cache vai para a pasta de trabalho (e apagado), por isso nao se paga |
| 2.5 | `tools/linux/build_deb.sh` | monta a arvore do pacote e chama o `dpkg-deb` |

## 5. Fase 3 — o pacote `.deb` (feito, a afinar)

| # | Tarefa | Estado |
|---|---|---|
| 3.1 | `debian/control` | `Architecture` (por build), `Depends` com as versoes (SDL3 3.2.10, FFmpeg 61/59/8, shaderc 1), `Recommends` (drivers) |
| 3.2 | `debian/copyright` | DEP5: o pacote e **GPL-2+** (o FFmpeg do Debian e `--enable-gpl`; o codigo do projeto e MIT, compativel). As licences de cada componente |
| 3.3 | `debian/changelog`, `debian/letsgo-recomp.desktop`, `debian/letsgo-recomp.1` | versao, entrada de menu, man page |
| 3.4 | `runtime/paths.c` | `rt_resource()` procura tambem em `<prefix>/share/letsgo-recomp` (o pacote: o programa em `<prefix>/bin`, os dados em `<prefix>/share`) |
| 3.5 | `lintian` | **por fazer** (o `lintian` nao esta instalado nesta maquina): `lintian build/dist/letsgo-recomp_0.6.0_amd64.deb` |
| 3.6 | icones | `hicolor/scalable/apps` (SVG) e `hicolor/1024x1024` (PNG). Faltam os tamanhos normais (16..512) → `tools/make_icons.py` com `rsvg-convert` |
| 3.7 | **a rever**: `Depends` com `libavcodec61` etc. fixa a versao do Debian 13; um `libavcodec62` (Debian 14) deixa de satisfazer a dependencia | `libavcodec61 | libavcodec62` (ou `>= 61` com risco) |
| 3.8 | **a rever**: o pacote leva 238 MB de zig | alternativa: `WITH_ZIG=0` (depende do `clang`) |

## 6. Fase 4 — testes (falta o ficheiro do jogo)

O `.deb` so esta "pronto" quando o jogo rodar de verdade. Precisa dos **ficheiros proprios do utilizador**
(`exefs` + `romfs` de *Let's Go, Eevee!* ou *Pikachu!*).

| # | Teste | Criterio de aceitacao |
|---|---|---|
| 4.1 | instalacao limpa | `sudo apt install ./letsgo-recomp_0.6.0_amd64.deb` → o programa no menu; os dados em `~/.local/share/letsgo-recomp` |
| 4.2 | set up | o launcher encontra a pasta do jogo, copia, gera o codigo e compila (zig) sem erros; o log sem `failed` |
| 4.3 | arranque do jogo | menu, overworld, batalha, captura; saves em `~/.local/share/letsgo-recomp/save` |
| 4.4 | F12 (menu no jogo) | abre, as paginas, aplica na hora |
| 4.5 | mods | instalar um `.zip` (traducao PT-BR) → o `bsdtar` extrai → o jogo mostra a traducao |
| 4.6 | controlador | SDL3 gamepad (Xbox/DualSense/Switch Pro) via `/dev/hidraw` |
| 4.7 | desempenho | 30 fps estaveis (media/P95/P99) no mesmo hardware que o Windows |
| 4.8 | regressao Windows | o build do Windows continua a passar (`make runtime-objs` em MSYS2) — as correcoes da Fase 0 sao partilhadas |
| 4.9 | `smoketest` | uma versao Linux do `tools/linux/smoketest.sh` do LAS Recomp (3 lancamentos + capturas) |

## 7. Fase 5 — documentacao (feito)

| # | Tarefa | Estado |
|---|---|---|
| 5.1 | `docs/COMPILAR-LINUX.md` | feito |
| 5.2 | `docs/DEBIAN.md` | feito |
| 5.3 | `README.md` | Linux na tabela de requisitos e a seccao do `.deb` |
| 5.4 | `CHANGELOG.md` | entrada "Linux / Debian port" |
| 5.5 | CI (opcional) | GitHub Actions a buildar o `.deb` em `debian:trixie` a cada push |

## 8. Riscos

| Risco | Impacto | Mitigacao |
|---|---|---|
| FFmpeg do Debian e GPL (o projeto e MIT) | o `.deb` tem de ser GPL-2+ | documentado em `debian/copyright`; alternativa = FFmpeg so-LGPL embutido (ver 3.8) |
| `sio_*` do SDL3 do Debian | linkage fragil | `--allow-shlib-undefined` (0.9); ou SDL3 >= 3.4 de fonte |
| FSR 3.1 indisponivel no Linux | falta o upscale FSR | decidido (1.4): o upscale in-house 2x/3x/4x ja existe |
| Sem o "grid" de vsync do Windows | a geracao de frames pode tremer | 1.3 (parcial): a taxa ja e lida; o alinhamento ainda nao |
| Codigo do jogo gerado no CPU do utilizador | 20 min na 1.ª vez | e o mesmo fluxo do Windows; o zig vai no pacote (1.5) |
| Sem `lld` na maquina de build | link falha | `LD=` (0.8) resolve; o contentor tem lld |
| O jogo nunca foi jogado no Linux | pode haver falhas de runtime que so aparecem com o jogo | Fase 4: precisa dos ficheiros do utilizador |

## 9. Ordem sugerida

1. **Fase 0** (feito) — o build Linux compila, linka e abre.
2. **Fase 1** (feito, excepto o grid de vsync) — mods, 2x, a taxa do ecra, o FSR 3.1 decidido.
3. **Fase 2** (feito) — o contentor e as ferramentas: o `.deb` constroi-se de forma repetivel.
4. **Fase 3** (feito, a afinar) — sai o primeiro `.deb` instalavel (57 MB).
5. **Fase 4** — **o proximo passo**: com os ficheiros do jogo, testar o fluxo completo.
6. **Fase 5** (feito) + `lintian` + os icones nos tamanhos normais.
