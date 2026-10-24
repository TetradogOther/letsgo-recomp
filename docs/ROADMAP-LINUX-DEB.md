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
| `tools/linux/build_appimage.sh` | gera `build/dist/letsgo-recomp_0.6.0_x86_64.AppImage` (o runtime, o gerador, o Zig e as libs) |
| O `.deb` instalado | o binario de `/usr/bin` abre e renderiza (o icone vem de `/usr/share/letsgo-recomp/icon.png`) |
| O AppImage | corre (com FUSE, ou a extrair-se quando nao ha FUSE) e abre o launcher |
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
| 1.3 | **P1** | **feito**: a "grelha" de vsync (o momento do ecra) nao tem equivalente no Linux como no Windows (o compositor nao a expoe), mas o driver sabe quando cada imagem chegou ao ecra (`VK_KHR_present_wait`, que o projecto ja usava para o log dos presents): e essa a blank que a mostrou. A geracao de frames usa-a como no Windows (`vblank_grid()`, `runtime/nvn/vulkan/device.c`); sem o driver's support, fica como estava | `LARECOMP_FG_NO_VSYNC_GRID=1` desliga |
| 1.4 | **P2** | **decidido**: FSR 3.1 stays Windows-only (the SDK's Linux build is not in the package); the log says so and the upscaler falls back to FSR 1. The in-house 2x/3x/4x and FSR 1 work | revisit if the AMD SDK's Linux build is worth the weight |
| 1.5 | **P1** | **decidido**: the package ships zig (as the Windows release does), so the player needs no compiler. `WITH_ZIG=0` builds a lighter package that depends on `clang` + `lld` | — |
| 1.6 | **P3** | the Switch's online services stay offline (as on Windows) | — |

## 4. Fase 2 — pipeline de build reproduzivel (feito)

| # | Tarefa | Estado |
|---|---|---|
| 2.1 | `tools/linux/Containerfile` | Debian 13 with the distribution's SDL3, FFmpeg, shaderc and Vulkan headers |
| 2.2 | `tools/linux/build_container.sh` | builds the packages in the container (podman or docker), with the user's own id (the files it writes belong to the user) |
| 2.3 | o gerador congelado | `tools/lasgen.spec` ja e multi-plataforma (trata do `libunicorn.so.2`); o `build_deb.sh` monta-o com PyInstaller |
| 2.4 | zig | `tools/fetch_zig.sh` ja suporta Linux (sha256 fixado). O "slim" (`tools/zig_slim.sh`) e so do Windows: em Linux o primeiro link demora ~13 s e o cache vai para a pasta de trabalho (e apagado), por isso nao se paga |
| 2.5 | `tools/linux/build_deb.sh` | monta a arvore do pacote e chama o `dpkg-deb` |
| 2.6 | `tools/linux/stage.sh` | a arvore comum aos dois pacotes (o runtime, o gerador, o Zig, os headers, os icones, a fonte, o `metainfo`) |

## 5. Fase 3 — os pacotes (feito, a afinar)

| # | Tarefa | Estado |
|---|---|---|
| 3.1 | `debian/control` | `Architecture` (por build), `Depends` com as versoes (SDL3 3.2.10, FFmpeg 61/59/8, shaderc 1), `Recommends` (drivers) |
| 3.2 | `debian/copyright` | DEP5: o pacote e **GPL-2+** (o FFmpeg do Debian e `--enable-gpl`; o codigo do projeto e MIT, compativel). As licences de cada componente |
| 3.3 | `debian/changelog`, `debian/letsgo-recomp.desktop`, `debian/letsgo-recomp.1` | versao, entrada de menu, man page |
| 3.4 | `runtime/paths.c` | `rt_resource()` procura tambem em `<prefix>/share/letsgo-recomp` (o pacote: o programa em `<prefix>/bin`, os dados em `<prefix>/share`) |
| 3.5 | `lintian` | corre na CI (o `lintian` esta no contentor) |
| 3.6 | icones | `hicolor/scalable/apps` (SVG) e `hicolor/1024x1024` (PNG), e os tamanhos normais (16..512) |
| 3.7 | `Depends` com `libavcodec61` etc. | corrigido: `libavcodec61 | libavcodec62` (e o mesmo para os outros) |
| 3.8 | o pacote leva 238 MB de zig | alternativa: `WITH_ZIG=0` (depende do `clang`) |
| 3.9 | a pasta dos dados | o codigo usava `~/.local/share/lasrecomp` e a documentacao prometia `~/.local/share/letsgo-recomp`: agora e `letsgo-recomp` (a pasta antiga e usada se for a que tem os saves) |
| 3.10 | as mensagens de erro em portugues | a tabela estava desalinhada (as do fluxo `.nsp`, que saiu): corrigida, com um `static_assert` que nao deixa as tabelas divergirem |

## 5b. Fase 3b — o AppImage (feito)

Um ficheiro com tudo, que corre sem instalar nada, para qualquer distribuicao de 64 bits.

| # | Tarefa | Estado |
|---|---|---|
| 3b.1 | `tools/linux/build_appimage.sh` | a arvore (a mesma do `.deb`, por `stage.sh`), o `AppRun`, e o ficheiro final: o runtime do AppImage com a imagem squashfs colada |
| 3b.2 | `tools/fetch_appimage_runtime.sh` | o runtime do AppImage (AppImageKit), com o sha256 fixado |
| 3b.3 | `tools/linux/bundle_libs.sh` | as bibliotecas dentro (SDL3, FFmpeg, shaderc e o que mais precisam), com o `patchelf`: o loader do Vulkan, as libs do driver, a stack X11/Wayland e a do audio sao as do sistema (o `RUNPATH` e do programa, para o driver nao ser afectado) |
| 3b.4 | `debian/letsgo-recomp.metainfo.xml` | os metadados da aplicacao (AppStream), para a integracao com as lojas e os menus |
| 3b.5 | a CI | `.github/workflows/packages.yml`: o `.deb` e o AppImage, em Debian 13 |
| 3b.6 | `docs/APPIMAGE.md` | como usar, como compilar, o que fazer sem FUSE |

## 6. Fase 4 — testes (falta o ficheiro do jogo)

O `.deb` (e o AppImage) so esta "pronto" quando o jogo rodar de verdade. Precisa dos **ficheiros proprios do
utilizador** (`exefs` + `romfs` de *Let's Go, Eevee!* ou *Pikachu!*).

**Ja testado sem o jogo:**

| Teste | Resultado |
|---|---|
| O launcher abre e desenha | ok (a captura em `build/smoke/launcher.png`) |
| O log nao tem erros | ok (`tools/linux/smoketest.sh`: READY) |
| A deteccao do jogo (`main.npdm`) | ok (com um `main.npdm` de mentira com o program id do Eevee) |
| A copia dos ficheiros do jogo | ok (`extracted/exefs/`) |
| **A imagem do RomFS** (`runtime/romfs_build.c`) | ok (`extracted/romfs.bin` construido a partir da pasta) |
| O codigo do jogo compilado com o zig e carregado | ok (as tabelas das quatro modulos; falta o NSO) |
| O crash e o backtrace | ok (`FATAL: cannot load extracted/exefs/main` + backtrace) |
| O `.deb` de dentro (`/usr/bin`) | ok (abre, desenha, o icone vem de `/usr/share`) |
| **O `.deb` instalado no sistema** | ok (Debian 13, `sudo apt install`: o launcher abre com as libs do sistema, o icone, o gerador e o Zig do pacote a correr) |
| **O AppImage** | ok (corre com FUSE ou a extrair-se; o launcher abre, o icone e a fonte vem de dentro) |
| **O gerador e o compilador no pacote** | ok (o runtime encontra-os em `usr/lib/letsgo-recomp`: o log do setup diz o caminho) |
| O codigo do Windows ainda compila | ok (`tools/linux/winsyntax.sh`: clang + headers do mingw) |
| Os programas lancados pelo nome | ok (o `posix_spawn` nao procura no PATH: corrigido) |
| O `lintian` | ok (sem queixas: `tools/linux/lintian.sh`) |

**Falta (precisa dos ficheiros do jogo):**

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
| 4.9 | `smoketest` | `tools/linux/smoketest.sh` (ja existe: o launcher + o log); falta a parte do jogo, com um save de teste |

### Os ficheiros do jogo

O port fica com o fluxo do Windows: a pasta com os ficheiros **extraidos** (o `exefs/` e o `romfs`), que o
utilizador traz da sua propria consola (TegraExplorer → `hactool`, com as chaves da consola). O port nao le chaves
nem descompacta `.nsp` — como no projeto original.

O `.nsp` que o utilizador tem (`Pokemon Let_s Go Eevee base.nsp`, 4,2 GB) esta, alem disso, truncado (faltam
37,4 MB) e cifrado (o formato "layered": o jogo dentro de *content archives* .nca, cifrados com as chaves da
consola) — por isso nao serve para o teste sem as chaves e sem um volcado completo.


## 7. Fase 5 — documentacao (feito)

| # | Tarefa | Estado |
|---|---|---|
| 5.1 | `docs/COMPILAR-LINUX.md` | feito |
| 5.2 | `docs/DEBIAN.md` | feito |
| 5.3 | `docs/APPIMAGE.md` | feito (o AppImage) |
| 5.4 | `README.md` | Linux na tabela de requisitos e a seccao do `.deb` e do AppImage |
| 5.5 | `CHANGELOG.md` | entrada "Linux / Debian port" |
| 5.6 | CI | GitHub Actions a buildar o `.deb` e o AppImage em `debian:trixie` a cada push |

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
| O AppImage e feito em Debian 13 (glibc 2.38+) | nao corre em distros mais antigas | e o mesmo do `.deb`: a documentacao diz a partir de que distro vai |
| As libs dentro do AppImage | podem divergir das do sistema | so o que e especifico da versao (SDL3, FFmpeg, shaderc); o Vulkan, o driver, o X11/Wayland e o audio sao os do sistema |

## 9. Ordem sugerida

1. **Fase 0** (feito) — o build Linux compila, linka e abre.
2. **Fase 1** (feito, excepto o grid de vsync) — mods, 2x, a taxa do ecra, o FSR 3.1 decidido.
3. **Fase 2** (feito) — o contentor e as ferramentas: os pacotes constroi-se de forma repetivel.
4. **Fase 3** (feito) — o `.deb` instalavel (57 MB) e o AppImage (Fase 3b).
5. **Fase 4** — **o que falta**: com os ficheiros do jogo, testar o fluxo completo (o `.deb` e o AppImage).
6. **Fase 5** (feito) + `lintian` (na CI) + os icones nos tamanhos normais.
