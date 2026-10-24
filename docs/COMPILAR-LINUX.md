# Compilar no Linux (Debian, Ubuntu)

Passo a passo do zero ate o jogo aberto, a partir do codigo-fonte. **Para so jogar, use o
[`.deb`](DEBIAN.md)** (ou a release para Windows, se preferires).

O runtime e multi-plataforma desde o inicio (veio do [LAS Recomp](https://github.com/peiikai/LASRecomp), que
tem um port Linux pronto); o que falta no Windows e o que este documento explica.

## O que precisa

- Debian 13 ("trixie") ou Ubuntu 24.04, 64 bits
- CPU com AVX2 (Intel Haswell / 2013 ou mais novo, AMD Excavator / Zen ou mais novo)
- GPU com Vulkan 1.3 e driver atualizado (NVIDIA, AMD ou Intel recentes)
- Uns 10 GB livres (os ficheiros do jogo, o codigo gerado e o build)
- **Os teus proprios ficheiros do jogo**: *Pokémon: Let's Go, Eevee!* ou *Pikachu!*, extraidos (a pasta com
  `exefs` e `romfs`). Este projeto nao fornece nem ensina a obter esses ficheiros ou as chaves.

## 1. As ferramentas (uma vez)

```bash
sudo apt update
sudo apt install clang lld make pkg-config python3-venv libsdl3-dev libavformat-dev libavcodec-dev \
    libavutil-dev libswscale-dev libvulkan-dev libshaderc-dev libvulkan-memory-allocator-dev \
    libarchive-tools curl file
```

Notas:

- `lld` e o linker (`make LD=` usa o linker do sistema, se nao o tiveres);
- `libshaderc-dev` e o compilador de GLSL para SPIR-V (o `Makefile` liga com `-lshaderc`; se a tua distribuicao
  o chamar `libshaderc_shared.so`, usa `make SHADERC=-lshaderc_shared`);
- `libarchive-tools` traz o `bsdtar`, que descompacta os mods (`.zip`, `.rar`, `.7z`).

## 2. O gerador do codigo do jogo

O gerador (que traduz o codigo ARM64 do jogo para C) precisa de Python:

```bash
python3 -m venv .venv
.venv/bin/pip install capstone unicorn lz4
```

## 3. Compilar o runtime

```bash
make -j$(nproc)
```

Isto gera `build/lasrecomp` (o runtime: o launcher e tudo o que substitui o Switch). Alteracoes ao runtime
recompilam em segundos.

## 4. Montar o jogo pelo launcher (o caminho mais simples)

```bash
./build/lasrecomp
```

No launcher, clica em **Selecionar pasta do jogo...** e escolhe a pasta com o jogo extraido (a que tem `exefs` e
`romfs`, ou um `romfs.bin`) - ou com o proprio `.nsp`, que o programa descompacta. Ele confirma se e o Eevee ou o
Pikachu, copia os ficheiros para `extracted/`, gera o
codigo do jogo com o `.venv` e compila-o (com o `clang` do sistema). E o mesmo fluxo da release, com as ferramentas
de desenvolvimento no lugar do gerador congelado e do Zig. Depois, clica em **Jogar**.

## 4b. Ou a mao

Cria a pasta `extracted/` na raiz do projeto com:

```
extracted/
  exefs/      main, main.npdm, rtld, sdk, subsdk0, subsdk1   (o ExeFS do jogo)
  romfs.bin   a imagem RomFS do jogo (uns 4,4 GB)
  romfs/      opcional: o RomFS extraido em pastas (util para mods; o jogo le o romfs.bin)
```

O codigo gerado depende do executavel exato: os remendos do gerador (`tools/patches.py`) e os ganchos do runtime so
sao enderecos do `main` 1.0.0 (tabela por build: Eevee e Pikachu, `tools/addrmap.py`) e ficam desligados
para qualquer outro. `extracted/` esta no `.gitignore` e nunca deve ir para o git.

Traduz o codigo do jogo para C (o resultado vai para `generated/`, fora do git) e compila. **Sempre com `-j`**: sem
ele, os ~920 ficheiros do jogo compilam um por um e passam de uma hora.

```bash
make gen
make -j$(nproc)
```

Isto gera tambem `build/lasgame.so` (o codigo do jogo).

## 5. Jogar

```bash
./build/lasrecomp
```

- Os saves ficam em `save/`, as configuracoes em `larecomp.ini` e os caches de shader em `cache/`, tudo na pasta do
  projeto (em modo dev) ou em `~/.local/share/letsgo-recomp` (como um pacote instalado).
- `--play` salta o launcher: `./build/lasrecomp extracted --play`.
- A primeira vez em cada area compila os shaders. Pode haver objetos aparecendo atrasados por um instante; da segunda
  vez em diante fica liso.

## 6. Os pacotes: o `.deb` e o AppImage

### O `.deb`

```bash
sudo apt install python3-pip dpkg-dev
tools/linux/build_deb.sh
```

Gera `build/dist/letsgo-recomp-<versao>-amd64.deb`. O script:

1. compila o runtime contra as bibliotecas da distribuicao (o pacote nao leva nenhuma biblioteca dentro);
2. congela o gerador do codigo do jogo com PyInstaller (para o jogador nao precisar de Python);
3. baixa o Zig (o compilador com que o codigo do jogo e compilado na maquina de quem joga);
4. monta a arvore do pacote (o programa, os dados, o icone, a fonte, a entrada de menu, a man page);
5. `dpkg-deb --build`.

### O AppImage

```bash
sudo apt install squashfs-tools patchelf
tools/linux/build_appimage.sh
```

Gera `build/dist/letsgo-recomp-<versao>-x86_64.AppImage`: um ficheiro com o runtime, o gerador, o Zig, os headers e
as bibliotecas de que o programa precisa (o loader do Vulkan e as libs do driver sao os do sistema). Ver
[APPIMAGE.md](APPIMAGE.md) para o usar.

### As opcoes (as duas)

| Opcao | O que faz |
|---|---|
| `WITH_ZIG=0` | o Zig nao vai dentro: o codigo do jogo e compilado com o `clang` do sistema (o pacote fica muito menor) |
| `WITH_HELPER=0` | o gerador nao vai dentro: o pacote so mostra o launcher |
| `BUNDLE_LIBS=0` | (so no AppImage) as bibliotecas ficam as do sistema, como no `.deb`: o ficheiro fica muito menor, mas precisa de `libsdl3-0` e FFmpeg instalados |
| `DEB_REVISION=<r>` | (so no `.deb`) a versao do pacote, em vez da que muda a cada build |
| `ARCH=arm64` | para Raspberry Pi e outros ARM de 64 bits |
| `JOBS=<n>` | quantos compiladores ao mesmo tempo |
| `DEPS=<prefix>` | uma pasta com SDL3 / FFmpeg / shaderc para ligar contra |

### Sem depender do que a maquina tem instalado

O contentor (Debian 13) constroi os dois pacotes sempre iguais, seja qual for a distribuicao da maquina:

```bash
tools/linux/build_container.sh              # os dois
tools/linux/build_container.sh deb          # so o .deb
tools/linux/build_container.sh appimage     # so o AppImage
```

Precisa de `podman` ou `docker`.

## 7. Problemas comuns

| Sintoma | O que fazer |
|---|---|
| `SDL3/SDL.h` nao encontrado | `sudo apt install libsdl3-dev` (ou `make DEPS=<prefix>`) |
| `libshaderc.so` nao encontrado | `sudo apt install libshaderc-dev` (ou `make SHADERC=-lshaderc_shared`) |
| `invalid linker name in argument '-fuse-ld=lld'` | `sudo apt install lld` (ou `make LD=`) |
| tela preta ou erro de Vulkan | atualiza o driver da GPU; precisa de Vulkan 1.3 (`vulkaninfo --summary`) |
| o launcher pede para montar o jogo de novo | o gerador ou os headers mudaram: escolhe a pasta de novo |
| `make gen` falha | confirma o `.venv` (`.venv/bin/pip install capstone unicorn lz4`) e que `extracted/exefs/main` existe |
| o jogo fecha sozinho | manda a saida do terminal (ou o `lasrecomp.log`, em `~/.local/share/letsgo-recomp/`) num issue |

## Para quem vai mexer no codigo

- [DEPURACAO.md](DEPURACAO.md): variaveis de diagnostico e o `tools/repro.sh`, que roda o jogo com entrada
  roteirizada e tira prints em quadros escolhidos.
- [HISTORICO.md](HISTORICO.md): como cada problema foi resolvido. E a melhor forma de entender o runtime.
- [ROADMAP-LINUX-DEB.md](ROADMAP-LINUX-DEB.md): o estado do port para Linux e do pacote.
- Mudou `runtime/cpu.h` ou `runtime/gamelib.h`? A biblioteca do jogo precisa de ser recompilada (`make -j`).
