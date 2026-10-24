# Instalar com o AppImage

O **AppImage** e um ficheiro unico com tudo o que o programa precisa: o runtime (o launcher e o que substitui o
Switch), o gerador do codigo do jogo, o compilador (zig) com que esse codigo e compilado na tua maquina, os
headers, o icone e a fonte do menu. **Nao leva os ficheiros do jogo**: precisas da tua propria copia, extraida.

Nao instala nada: e um ficheiro que se executa. Serve para qualquer distribuicao de 64 bits (Debian, Ubuntu,
Fedora, Arch...), nao so para as que temem um pacote.

## Requisitos

- Linux de 64 bits (x86-64 ou aarch64)
- CPU com AVX2 (Intel Haswell / 2013 ou mais novo, AMD Excavator / Zen ou mais novo)
- GPU com Vulkan 1.3 e driver atualizado
- ~6 GB livres (os ficheiros do jogo e o codigo compilado)
- **FUSE**, para o AppImage se montar a si mesmo (Debian e Ubuntu ja o trazem; se nao, ve "Sem FUSE" abaixo)

## Instalar

1. Descarrega o `LetsGoRecomp-<versao>-x86_64.AppImage` das [releases](../../releases).
2. Dale permissao de execucao:

   ```bash
   chmod +x LetsGoRecomp-0.6.1-x86_64.AppImage
   ```

3. Executa-o:

   ```bash
   ./LetsGoRecomp-0.6.1-x86_64.AppImage
   ```

Depois, o launcher abre: clica em **Selecionar pasta do jogo...** e escolhe a pasta com a tua copia extraida (a que
tem `exefs` e `romfs`, ou um `romfs.bin`). O resto faz-se sozinho (copia, imagem do RomFS, geracao do codigo do
jogo, compilacao). Como obter essa pasta: [DEBIAN.md](DEBIAN.md#como-obter-essa-pasta).

## Os teus ficheiros

Tudo o que o programa escreve fica em `$XDG_DATA_HOME/letsgo-recomp` (`~/.local/share/letsgo-recomp` por omissao) -
**a mesma pasta** que o pacote `.deb` usa, para que se troques de um para o outro sem perder os saves:

| | |
|---|---|
| `extracted/` | os ficheiros do jogo (copiados) e o codigo do jogo compilado |
| `save/` | os saves |
| `cache/` | o cache de shaders (e as texturas da interface 2x) |
| `larecomp.ini` | as configuracoes |
| `lasrecomp.log` | o log (a execucao anterior fica em `lasrecomp-prev.log`) |

Para usar outra pasta: `LARECOMP_DATA_ROOT=<pasta> ./LetsGoRecomp.AppImage`.

## Sem FUSE

O AppImage monta-se a si mesmo com FUSE. Se a tua distribuicao nao o trouxer (ou se correes dentro de um contentor
ou de um `chroot`), o proprio AppImage extrai-se e corre:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./LetsGoRecomp-0.6.1-x86_64.AppImage
```

Ou, para sempre, num terminal:

```bash
./LetsGoRecomp-0.6.1-x86_64.AppImage --appimage-extract
./squashfs-root/usr/bin/letsgo-recomp
```

## Desinstalar

Apaga o ficheiro. O que o programa escreveu fica em `~/.local/share/letsgo-recomp`: apaga essa pasta se quiseres
nao deixar nada.

## Compilar a partir do codigo

```bash
sudo apt install clang lld make pkg-config python3-venv python3-pip libpython3-dev libsdl3-dev libavformat-dev \
    libavcodec-dev libavutil-dev libswscale-dev libvulkan-dev libshaderc-dev libvulkan-memory-allocator-dev \
    libarchive-tools squashfs-tools patchelf file
tools/linux/build_appimage.sh
```

Sai `build/dist/letsgo-recomp-<versao>-x86_64.AppImage`. O script tambem aceita:

| Variavel | O que faz |
|---|---|
| `BUNDLE_LIBS=0` | as bibliotecas ficam as do sistema (como no `.deb`): o AppImage fica muito menor, mas precisa de `libsdl3-0` e FFmpeg instalados |
| `WITH_ZIG=0` | o zig nao vai dentro: o codigo do jogo e compilado com o `clang` do sistema (o pacote fica muito menor) |
| `WITH_HELPER=0` | o gerador nao vai dentro: o AppImage so mostra o launcher |
| `ARCH=aarch64` | para Raspberry Pi e outros ARM de 64 bits |

Para um build que nao dependa do que a maquina tem instalado (o mesmo `.deb` e AppImage, sempre em Debian 13):

```bash
tools/linux/build_container.sh appimage     # so o AppImage
tools/linux/build.sh --container             # os dois
```

Mais em [COMPILAR-LINUX.md](COMPILAR-LINUX.md).

## Problemas

O log esta em `~/.local/share/letsgo-recomp/lasrecomp.log`. Manda-o num issue do
[repositorio](https://github.com/TetradogOther/letsgo-recomp/issues).
