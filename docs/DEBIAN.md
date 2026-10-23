# Instalar no Debian / Ubuntu

O pacote `.deb` leva o runtime (o launcher e o que substitui o Switch), o gerador do codigo do jogo, o compilador
com que esse codigo e compilado na tua maquina, os headers do codigo do jogo, o icone e a fonte do menu. **Nao leva
os ficheiros do jogo**: precisas da tua propria copia, extraida.

## Requisitos

- Debian 13 ("trixie") ou Ubuntu 24.04, 64 bits (o pacote e construido com glibc 2.38 ou mais novo)
- CPU com AVX2 (Intel Haswell / 2013 ou mais novo, AMD Excavator / Zen ou mais novo)
- GPU com Vulkan 1.3 e driver atualizado
- ~6 GB livres (os ficheiros do jogo e o codigo compilado)

## Instalar

```bash
sudo apt install ./letsgo-recomp_0.6.0_amd64.deb
```

Depois, **Let's Go Recomp** aparece no menu de aplicacoes. Tambem pode ser lancado pela linha de comandos:

```bash
letsgo-recomp
```

## Os teus ficheiros do jogo

No launcher, clica em **Selecionar pasta do jogo...** e escolhe a pasta com a tua copia extraida (a que tem `exefs` e
`romfs`, ou um `romfs.bin`).

A primeira vez, o launcher:

1. copia os ficheiros do jogo para a tua pasta de dados;
2. traduz o codigo ARM64 do jogo para C (uns minutos);
3. compila esse codigo para o teu computador (uns 20 minutos num CPU com 20 threads, mais com menos).

Isto so acontece uma vez por jogo. O codigo gerado e do teu ficheiro exacto: uma actualizacao do jogo (1.0.1,
1.0.2) obriga a refazer.

## Onde ficam as coisas

Tudo o que o programa escreve fica em `$XDG_DATA_HOME/letsgo-recomp` (`~/.local/share/letsgo-recomp` por omissao):

| | |
|---|---|
| `extracted/` | os ficheiros do jogo (copiados) e o codigo do jogo compilado |
| `save/` | os saves |
| `cache/` | o cache de shaders (e as texturas da interface 2x) |
| `larecomp.ini` | as configuracoes |
| `lasrecomp.log` | o log (a execucao anterior fica em `lasrecomp-prev.log`) |

Para usar outra pasta: `LARECOMP_DATA_ROOT=<pasta> letsgo-recomp`.

## Controladores

Funcionam como no Windows: qualquer mando que o SDL3 reconheca (Xbox, DualShock 4, DualSense, Switch Pro, Joy-Con,
8BitDo...). Para o rumble, os LEDs e o giroscopio dos comandos da PlayStation/Switch, o utilizador precisa de acesso
a `/dev/hidraw*` (quase todas as distribuicoes dao-no pelas regras do udev do Steam).

## O que **nao** funciona (ainda) no Linux

- **FSR 3.1** (o upscale): so o Windows tem a biblioteca da AMD. O upscale in-house (2x/3x/4x) e o FSR 1 funcionam.
- **Geracao de frames**: funciona, mas o alinhamento com o ecra nao e tao preciso como no Windows (o Windows le a
  temporizacao do compositor; no Linux so se conhece a taxa do ecra).
- **Nao ha**: multiplos jogadores, Poké Ball Plus, nem as funcoes online (o jogo fica offline, como no Windows).

## Desinstalar

```bash
sudo apt remove letsgo-recomp
```

Os teus ficheiros (save, cache, o codigo do jogo) ficam em `~/.local/share/letsgo-recomp`: apaga essa pasta se
quiseres nao deixar nada.

## Problemas

Manda o `~/.local/share/letsgo-recomp/lasrecomp.log` (e o `lasrecomp-prev.log`, o da execucao anterior) num issue do
[repositorio](https://github.com/TetradogOther/letsgo-recomp/issues). Um crash escreve `*** signal ...` e um
backtrace no log.

Compilar a partir do codigo: [COMPILAR-LINUX.md](COMPILAR-LINUX.md).
