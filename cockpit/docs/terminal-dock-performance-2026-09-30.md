# Terminais, encaixe e resize — investigação de 2026-09-30

## Ensaio controlado

- Base: `main` em `bd5cda24`, Windows, build Flutter **debug**, `COCKPIT_PERF=1`.
- Instância debug e workspace temporário isolados. Abrimos 10 shells PowerShell:
  o primeiro no novo workspace, mais quatro em splits alternados e outros cinco
  como abas. Os dez foram confirmados por `list-workspaces --json`; o workspace
  e a instância de teste foram fechados após a medição.
- As métricas abaixo vêm do log local de performance da instância debug. São
  tempos indicativos de JIT e shells ociosos, não um baseline de release nem
  uma medição de agentes emitindo saída continuamente.

| Medida | Resultado no ensaio de 10 shells |
| --- | --- |
| Criação síncrona da sessão (`terminalOpen`) | 10 amostras: 0,81–1,33 ms |
| Criação → callback pós-frame (`terminalOpenFrame`) | 10 amostras: 59–135 ms |
| Criação → primeiro lote de saída (`terminalFirstOutput`) | 10 amostras: 104–157 ms |
| Frames na janela de atividade | 17 de 31 acima de 16,7 ms; p95 98 ms; máximo 119 ms |
| Frames lentos individuais | vários com build de 56–101 ms e raster de 2–6 ms |

O shell e o gateway não explicam sozinhos o atraso percebido ao abrir uma aba:
o trecho síncrono ficou perto de 1 ms, enquanto o próximo frame frequentemente
levou mais de 60 ms. O primeiro shell após iniciar a instância foi um caso frio:
43,6 ms de criação, 200 ms até o pós-frame e 2,20 s até a primeira saída.

## Onde o trabalho acontece

1. **Abrir terminal.** `CockpitViewModel._buildTerminal` constrói a sessão e
   inicia o gateway; `notifyListeners` reconstrói `_CenterPanel`. O painel
   recorre por workspaces e splits, e cada `PaneView` mantém as abas num
   `IndexedStack`. A diferença entre `terminalOpen` e `terminalOpenFrame`, junto
   dos `slowFrame` dominados por build, aponta para custo de construção/layout
   da interface. A primeira saída é uma medida separada do boot do shell.
2. **Encaixar abas.** `PaneDropZone` atualiza a prévia quando a zona de drop muda;
   o commit chama `moveTabToPane`, `moveTabToNewSplit` ou `moveTabToIndex`. Essas
   operações substituem a árvore e notificam a ViewModel global. Portanto o
   mesmo painel central e as abas mantidas montadas entram no rebuild. As
   métricas `terminalDockFrame` foram instaladas nesses três caminhos, mas não
   houve arraste controlado neste ensaio.
3. **Redimensionar.** Cada delta do divisor chama `resizeSplitBy`, substitui a
   árvore imutável e notifica todos os ouvintes. `_CenterPanel` observa a
   ViewModel inteira; todos os workspaces continuam em `IndexedStack`. No
   Ghostty, a `TerminalView` inativa permanece em `Offstage`, que ainda participa
   do layout quando as constraints mudam. Isso torna o custo por delta
   proporcional à árvore e às views montadas. A métrica
   `terminalResizeFrame` agrupa deltas do mesmo frame, mas ainda precisa de um
   arraste real para quantificar esse caminho.

O monitor de processos levou cerca de 1–1,7 s por varredura em algumas amostras.
Esse tempo inclui `await Process.run(powershell.exe, Get-CimInstance ...)` e
**não** significa que a UI ficou bloqueada por 1 s. É uma fonte possível de
contenção de CPU/processos a investigar separadamente.

## Workspace complexo no Windows

Um segundo ensaio usou dois projetos do repositório e cinco terminais em cada
um (10 shells, mais o terminal interno do Cockpit). Na máquina havia cerca de
838 processos; uma execução isolada da consulta usada pelo monitor levou
842 ms e produziu 324 KiB de JSON. Com a versão anterior, oito trocas reais
entre os projetos levaram 60–97 ms até o próximo frame, enquanto a resposta
da CLI levou 13–21 ms. A janela de 95 frames teve 38 acima de 16,7 ms e p95
de 92 ms; essa janela inclui a preparação do cenário e as trocas. A diferença
entre a resposta da CLI e `workspaceSwitch` mostra que a espera percebida está
principalmente no frame.

O monitor fazia `requestPoll` quando uma sessão se tornava visível. Trocar de
projeto aciona a visibilidade das abas, portanto disparava a consulta CIM mesmo
sem mudança na árvore de processos. O ajuste retira esse disparo e mantém
sondagens por atividade do terminal e uma verificação periódica de segurança.
No Windows, a verificação periódica passa de 2/5/10 s para 8/20/30 s
(visível/ocioso/janela inativa). Os intervalos de outras plataformas não mudam.
Após o ajuste, repetimos oito trocas com os mesmos dez terminais: nenhuma
varredura apareceu na janela da troca. O próximo frame ainda levou 79–104 ms
no build debug. Assim, a sondagem de visibilidade era uma fonte confirmada de
carga extra no Windows, mas sua remoção não eliminou a latência do layout.

O painel central também passa a reutilizar o widget de cada workspace e cada
um observa apenas sua própria árvore/foco. Isso evita reconstruir todas as
árvores montadas em cada notificação global da ViewModel. Os workspaces ainda
ficam montados no `IndexedStack`, portanto a mudança de tamanho pode continuar
a recalcular o layout das views inativas. Não há medição de drag real nesta
sessão; a hipótese de custo de layout por resize continua aberta.

Ao reabrir pela CLI um workspace já cadastrado, `addProject` agora usa
`selectProject`. Antes ele alterava `_selectedProjectId` diretamente, sem a
rotina de ativação/observação e sem emitir `workspaceSwitch`; por isso o
primeiro ensaio de troca pela CLI não media o caminho real da interface.

## Próxima medição visual

Em um build **profile**, iniciar com `COCKPIT_PERF=1`. Repetir com 5 e 10
terminais no mesmo workspace: (a) arrastar uma aba entre panes e encaixá-la;
(b) arrastar o divisor por alguns segundos. Comparar `terminalDockFrame`,
`terminalResizeFrame`, `slowFrame` e `frame`, além de uma captura de CPU no
DevTools. Isso distinguirá o custo do rebuild global do custo de layout das
views ocultas. A automação de interface disponível nesta sessão não permite
controlar aplicativos de terminal, então esse gesto visual não foi medido aqui.
