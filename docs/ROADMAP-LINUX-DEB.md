# Roteiro: port nativo para Linux e empacotamento `.deb` (Debian)

_23/10/2026. Documento de trabalho: o que já foi validado neste repositório, o que falta para o jogo rodar no
Debian e como empacotar um `.deb` instalável._

## 1. Onde estamos

O runtime já é multi-plataforma: veio do [LAS Recomp](https://github.com/peiikai/LASRecomp), que tem um port Linux
pronto (`runtime/platform/linux.c`, tabelas HLE em seções ELF, `__start_`/`__stop_`). O que **não** existia neste
fork era o *empacotamento* e algumas correções que a janela "Windows" do fork deixou de lado.

**Validado nesta máquina (Debian 13 "trixie", x86-64, AMD Radeon 760M / RADV):**

| Verificação | Resultado |
|---|---|
| `make runtime-objs` (PLATFORM=linux) | compila |
| `make` (link do runtime) | linka (`build/lasrecomp`, 7,7 MB) |
| Execução | abre a janela **"Let's Go Recomp"** (774x900) e renderiza o launcher (ícone, fonte Baloo2, páginas) |
| Vulkan |RADV 1.4.305 + lavapipe detectados; swapchain e anéis de memória OK |

O jogo em si **ainda não foi testado**: exige os ficheiros próprios do utilizador (`exefs`/`romfs`) e o primeiro
"set up" compila ~920 ficheiros de código do jogo (zig/clang), como no Windows.

## 2. Fase 0 — correções de portabilidade (feito)

O build Linux não compilava. Estas correções já estão aplicadas (branch `feature/linux-debian-port`):

| # | Onde | Problema | Correção |
|---|---|---|---|
| 0.1 | `runtime/platform/linux_compat.h` | `rmdir` sem declaração (`runtime/mods.c`) | `#include <unistd.h>` |
| 0.2 | `runtime/paths.c`, `runtime/ui/launcher_lg.mm` | `SDL_LoadPNG` só existe no SDL3_image (não está no SDL3) | novo `runtime/png.c` (stb_image, já vendorizado) → `rt_png_surface()` |
| 0.3 | `runtime/nvn/vulkan/device.c` | `SDL_SavePNG` (mesma origem) | `rt_png_write()` (stb_image_write) |
| 0.4 | `runtime/ui2x.c` | duas implementações do stb no mesmo link → símbolos duplicados | o stb passa a viver só em `runtime/png.c` |
| 0.5 | `runtime/hle/movie.c` | `stat`/`S_ISREG` sem `<sys/stat.h>` | include |
| 0.6 | `runtime/platform/linux.c` | `RT_APP_NAME` indefinido (falta `paths.h`) | include |
| 0.7 | `third_party/fidelityfx/.../ffx_api.h` | `__declspec` (MSVC) no header do FSR 3.1 | `__attribute__((visibility("default")))` fora do MSVC |
| 0.8 | `Makefile` | `-fuse-ld=lld` obrigatório | `LD ?= lld` (usar `make LD=` num sistema sem lld) |
| 0.9 | `Makefile` | o SDL3 do Debian deixa `sio_*` (libudev) indefinidos e o linker recusa | `-Wl,--allow-shlib-undefined` |

**Nota de licenciamento:** a Correção 0.2/0.3 removeu a dependência do SDL3_image (que nem estava declarada no
Makefile do Windows) e passa a usar o `third_party/stb` já vendorizado. Menos uma dependência, mesmo código nas
duas plataformas.

## 3. Fase 1 — functionality que ainda é só-Windows

Itens que não impedem compilar, mas que o utilizador nota no Linux. Cada um com uma decisão explícita.

| # | Prior. | Onde | Situação | Decisão a tomar |
|---|---|---|---|---|
| 1.1 | **P0** | `runtime/mods.c:196` | instalar mod usa `C:\Windows\System32\tar.exe` | usar `bsdtar` (libarchive, `libarchive-tools` no Debian): `.zip`, `.rar` e `.7z` como no Windows; alternativa: `tar` do GNU só para `.tar` |
| 1.2 | **P1** | `runtime/ui2x.c:38,211` | a interface 2x baixa o `waifu2x-ncnn-vulkan-**windows**` com `curl.exe`/`tar.exe` | existe release **linux** (36 MB, sha256 `848e0fba…`): trocar o nome da ferramenta e usar `curl` + `unzip`/`bsdtar` |
| 1.3 | **P1** | `runtime/nvn/vulkan/device.c:856` | `vk_display_hz()` devolve 0 no Linux (no Windows usa o DWM) | sem isto, a geração de frames "Auto" não escolhe multiplicador e a grelha de vsync fica desligada; implementação Linux: `VK_KHR_display`/`SDL_GetCurrentDisplayMode` ou medição do próprio present |
| 1.4 | **P2** | `runtime/nvn/vulkan/fsr3.cpp` | FSR 3.1 só no Windows (`amd_fidelityfx_vk.dll`) | decidir: (a) ficar só no Windows (o upscale in-house 2x/3x/4x já cobre), ou (b) construir a `libamd_fidelityfx_vk.so` do SDK FidelityFX (pesado, ~1 h de build) |
| 1.5 | **P2** | `runtime/gamebuild.c:130` | o compilador do código do jogo: `zig` (embarcado) ou `/usr/bin/clang` (só em modo dev) | no `.deb`, embarcar o `zig` (igual ao Windows) para não depender de um compilador instalado; alternativamente, depender de `clang`+`lld` |
| 1.6 | **P3** | `runtime/services/network.c`, `offline.c` | serviços online do Switch | confirmar que ficam inativos e não travam (o port Windows já é "offline") |

## 4. Fase 2 — pipeline de build reproduzível

O `.deb` tem de ser built num ambiente controlado (glibc, FFmpeg, shaderc iguais em todas as máquinas).

| # | Tarefa | Detalhe |
|---|---|---|
| 2.1 | `tools/linux/Containerfile` | imagem `debian:trixie` com `clang lld make cmake ninja-build python3-venv pkg-config libsdl3-dev libav*-dev libswscale-dev libvulkan-dev libshaderc-dev libvulkan-memory-allocator-dev libarchive-tools patchelf` |
| 2.2 | `tools/linux/build_deps.sh` | decidir: usar as libs do Debian (recomendado: `.deb` multiarch, sem libs embutidas) ou compilar SDL3/FFmpeg/shaderc de fonte (como o AppImage do LAS Recomp) |
| 2.3 | `tools/linux/gen_helper.sh` | congelar o gerador com PyInstaller em Linux (`tools/lasgen.spec` já é multi-plataforma: trata do `libunicorn.so.2`); precisa de um venv com `capstone unicorn lz4` |
| 2.4 | `tools/fetch_zig.sh` | **já suporta Linux** (`x86_64-linux`, `aarch64-linux`, sha256 fixado); falta a variante "slim" para Linux (`tools/zig_slim.sh` é só Windows) ou aceitar o link mais lento na 1.ª execução |
| 2.5 | `tools/linux/package.sh` | monta `build/deb/` com a árvore final do pacote |

## 5. Fase 3 — o pacote `.deb`

Estrutura alvo (política Debian: programas em `/usr/bin`, dados em `/usr/share`):

```
/usr/bin/letsgo-recomp                     -> symlink para o binário real
/usr/lib/letsgo-recomp/lasrecomp           (o runtime + launcher)
/usr/lib/letsgo-recomp/lasgen/             (gerador congelado, PyInstaller)
/usr/lib/letsgo-recomp/zig/                (compilador do código do jogo)
/usr/lib/letsgo-recomp/gamelib-src/        (cpu.h, simd.h, gamelib.h, gamelib_entry.c, hle_symbols.txt)
/usr/lib/letsgo-recomp/icon.png
/usr/lib/letsgo-recomp/Baloo2-SemiBold.ttf (+ OFL.txt)
/usr/share/applications/letsgo-recomp.desktop
/usr/share/icons/hicolor/256x256/apps/letsgo-recomp.png
/usr/share/doc/letsgo-recomp/{copyright,changelog.Debian.gz}
```

| # | Tarefa | Nota |
|---|---|---|
| 3.1 | `debian/control` | `Package: letsgo-recomp`, `Section: games`, `Architecture: amd64 arm64`, `Depends: libc6, libstdc++6, libsdl3-0 (>= 3.2.10), libvulkan1, libshaderc1, libavcodec61, libavformat61, libavutil59, libswscale8, libgcc-s1, bsdtar, curl, ca-certificates` |
| 3.2 | `debian/rules` | `dh $@ --with buildinfo`; compilar com `LD=` (sem lld se não houver) e `SHADERC=-lshaderc` |
| 3.3 | `debian/copyright` | **decisão de licenciamento**: o FFmpeg do Debian é GPL-2.0+ → o `.deb` tem de ser GPL-2.0+ (o código do projeto é MIT, compatível). Alternativa: compilar um FFmpeg só-LGPL e embutir a `.so` (mas isso quebra a política multiarch do Debian) |
| 3.4 | `rt_resource()` | procurar também em `<prefix>/share/letsgo-recomp` (hoje só procura ao lado do executável e em `../Resources`) |
| 3.5 | `debian/*.desktop`, ícone | `docs/icon/icon.svg` → PNGs em `hicolor` (o `tools/make_icons.py` já existe) |
| 3.6 | `lintian` | `lintian --no-tag-display-limit build/letsgo-recomp_0.6.0_amd64.deb`: zero warnings esperados (o `.deb` não leva ficheiros do jogo nem chaves) |
| 3.7 | `dh_install` / exclusões | nada de `extracted/`, saves, `*.log`; o log vai para `~/.local/share/lasrecomp/lasrecomp.log` (já implementado em `runtime/paths.c` + `runtime/platform/linux.c`) |

## 6. Fase 4 — testes

O `.deb` só está "pronto" quando o jogo rodar de verdade. Precisa dos **ficheiros próprios do utilizador**
(`exefs` + `romfs` de *Let's Go, Eevee!* ou *Pikachu!*).

| # | Teste | Critério de aceitação |
|---|---|---|
| 4.1 | instalação limpa | `sudo apt install ./letsgo-recomp_0.6.0_amd64.deb` → `letsgo-recomp` no menu deApplications; dados em `~/.local/share/lasrecomp` |
| 4.2 | set up | o launcher encontra a pasta do jogo, copia, gera o código e compila (zig) sem erros; log sem `failed` |
| 4.3 | arranque do jogo | menu, overworld, batalha, captura; saves em `~/.local/share/lasrecomp/save` |
| 4.4 | F12 (menu no jogo) | abre, páginas de gráficos/áudio/controlos, aplica na hora |
| 4.5 | mods | instalar um `.zip` (tradução PT-BR) → `bsdtar` extrai → o jogo mostra a tradução |
| 4.6 | controlador | SDL3 gamepad (Xbox/DualSense/Switch Pro) via `/dev/hidraw` |
| 4.7 | desempenho | 30 fps estáveis (média/P95/P99 de frametime) no mesmo hardware que o Windows |
| 4.8 | regressão | o build do Windows continua a passar (`make runtime-objs` em MSYS2) — as correções da Fase 0 são partilhadas |
| 4.9 | `smoketest` | versão Linux do `tools/linux/smoketest.sh` do LAS Recomp (3 lançamentos + capturas) |

## 7. Fase 5 — documentação e release

| # | Tarefa |
|---|---|
| 5.1 | `docs/COMPILAR-LINUX.md` (passo a passo, como o `COMPILAR-WINDOWS.md`) |
| 5.2 | `docs/DEBIAN.md` (como instalar o `.deb`, onde ficam os dados, cómo reportar problemas) |
| 5.3 | `README.md`: tabela de requisitos com Linux/Debian, e secção "Instalação no Debian" |
| 5.4 | `CHANGELOG.md`: entrada "port Linux / pacote .deb" |
| 5.5 | CI (opcional): GitHub Actions a buildar o `.deb` em `debian:trixie` a cada push |

## 8. Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| FFmpeg do Debian é GPL (o projeto é MIT) | o `.deb` tem de ser GPL-2.0+ | documentar em `copyright`; alternativa = FFmpeg só-LGPL embutido (ver 3.3) |
| `sio_*` do SDL3 do Debian | linkage frágil | `--allow-shlib-undefined` (0.9); ou SDL3 >= 3.4 de fonte |
| FSR 3.1 indisponível no Linux | falta o upscale FSR | o upscale in-house 2x/3x/4x já existe; decidir em 1.4 |
| Sem o "grid" de vsync do Windows | a geração de frames pode tremer | implementar 1.3 antes de anunciar frame generation no Linux |
| Código do jogo gerado no CPU do utilizador | 20 min na 1.ª vez | é o mesmo fluxo do Windows; embarcar o zig (1.5) |
| Sem `lld` na máquina de build | link falha | `LD=` (0.8) resolve; o contentor terá lld |

## 9. Ordem sugerida

1. **Fase 0** (feito) — o build Linux compila, linka e abre.
2. **Fase 1.1 + 1.2** (mods e 2x) —small, sem risco.
3. **Fase 2** (contentor + ferramentas) — o `.deb` passa a ser built de forma repetível.
4. **Fase 3** (empacotamento) — sai o primeiro `.deb` instalável.
5. **Fase 4** (testes com os ficheiros do jogo) — valida o jogo de verdade.
6. **Fase 1.3** (vsync/refresh) e **5** (docs) — polimento e anúncio.
