# Direção visual — modo Grafo do Cockpit

Proposta baseada no widget atual (`workspace_graph_view.dart`) e no pedido de visão macro. Não substitui uma revisão visual do app em execução. Preserva o grafo em tela inteira, o duplo clique para abrir terminal, o arrasto apenas posicional e os vínculos por ID.

## Leitura da tela atual

- Os cards de 210 × 124 px mostram nome, ferramenta, estado e contexto, mas cada informação tem praticamente o mesmo peso. Falta uma leitura rápida de quais terminais pedem atenção.
- O estado usa somente a cor do texto. O host desconectado pode coexistir com uma aparência de sessão ativa. Uma cor isolada também é pouco acessível.
- O hover reúne 14 linhas de texto bruto, incluindo valores indisponíveis. É completo, mas difícil de escanear.
- Conexões planejadas e trocas observadas compartilham a mesma geometria. Seleção e observação usam a mesma cor de destaque; o significado da linha não fica claro sem uma legenda.
- O inspector mistura função, recuperação de sessão, compactação e vínculos numa coluna de botões de mesmo destaque. Os vínculos exibem IDs, embora o usuário pense em nomes de boxes.
- Cards temporários têm borda âmbar e um rótulo, mas se parecem com terminais persistentes e não deixam tão claro que são filhos controlados pelo terminal principal.

## Princípio visual

**Mapa operacional, não painel de métricas.** A leitura em 3 segundos deve responder: (1) quem está trabalhando, (2) onde há atenção, (3) quem está ligado a quem. Os detalhes de tokens, CPU e fonte ficam em um popover estruturado e no inspector.

## Wireframe

```text
┌ Cockpit / Workspace                    [ + Box ] [ Ligar ] [ − 100% + ] [ Terminais ] ┐
│                                                                                       │
│  LEGENDA  ● trabalhando  ◌ aguardando  ○ ocioso  ⨯ encerrado                         │
│          ┄ planejado   ━→ troca observada   ┈ subagente temporário                   │
│                                                                                       │
│        ┌──────────────────────────────┐                                               │
│        │ ●  Planner             Claude │                                               │
│        │ Arquiteta a demanda          │                                               │
│        │ Contexto 62%  ██████░░░░     │                                               │
│        │ 84k tokens · agora           │                                               │
│        └──────────────┬───────────────┘                                               │
│                       ┈┈┈┈┈┈┈┈┈┈┈┈┈┐                                                    │
│                       ┌───────────▼─────────────┐                                      │
│                       │ ◈ Subagente · pesquisa  │                                      │
│                       │ Temporário · Claude     │                                      │
│                       └─────────────────────────┘                                      │
│                                                                 ┌───────────────────┐ │
│  ┌──────────────────────────────┐  ━━━━━━━━━━━━━━━━━━━━━━━━━━━→ │ INSPECTOR         │ │
│  │ ◌ Frontend             Codex │                                 │ Frontend          │ │
│  │ Interface do grafo           │                                 │ Função · editar   │ │
│  │ Contexto 81% ████████░░      │                                 │ Métricas · fonte  │ │
│  │ ⚠ Compactação sugerida       │                                 │ Vínculos por nome │ │
│  └──────────────────────────────┘                                 │ [Abrir terminal]  │ │
│                                                                   └───────────────────┘ │
│  Arraste box: organiza · Arraste fundo: navega · Roda: zoom                            │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

## Componentes e estados

### Card principal

- Alvo inicial: aproximadamente 232 × 132 px; manter título em uma linha e função em no máximo duas. O tamanho exato deve ser validado em 100%, 75% e 50% de zoom.
- Cabeçalho: indicador de estado **com forma + cor**, nome em destaque e ferramenta/modelo em texto secundário. Estado e ferramenta não devem depender de tooltip.
- Corpo: função curta ou “Função não definida”. Exibir contexto em barra com porcentagem; se não houver métrica, mostrar “Contexto indisponível” sem barra vazia.
- Rodapé contextual: tokens totais quando disponíveis; alerta de compactação/handoff somente ao cruzar limiares atuais. Evitar mostrar CPU/RAM em todo card para preservar legibilidade do mapa.
- Seleção: contorno e halo discretos; vizinhos ficam em destaque, demais boxes e conexões reduzem contraste. O halo não altera área de layout nem fluxo de ponteiro.

### Card temporário

- Menor que o principal, fundo levemente diferente, ícone de ramo/diamante e borda tracejada. Exibir “Subagente temporário”, tipo e ferramenta; nunca sugerir que tem aba própria.
- Linha pontilhada até o pai, sempre com cor e padrão próprios. Duplo clique abre o pai. Se houver vários filhos, escalonar visualmente sem sobrepor o inspector.
- Encerramento remove o card. Host desconectado mantém o estado explícito enquanto a fonte não confirma o fim.

### Conexões

- **Planejada:** cinza tracejado, seta discreta. **Observada:** traço contínuo na cor de atividade, com seta. **Subagente:** pontilhado âmbar, ligado ao pai. Legenda persistente e compacta no canto.
- Quando planejada e observada coincidirem, evitar duas linhas sobrepostas: uma linha contínua com pequeno marcador de “planejada” ou legenda no inspector. O desenho precisa continuar ancorado aos IDs após arrasto.
- Mensagens `SendMessage` do Claude observadas pelo hook criam uma conexão dirigida. Quando o endereço do destinatário ainda não corresponde com segurança a uma aba, mostrar um box de destinatário não vinculado; quando a identidade da aba chegar, substituir esse box pela conexão entre os terminais. O conteúdo da mensagem não entra no grafo.
- Priorizar clareza sobre animações permanentes; se houver indicação de troca recente, animar brevemente apenas a conexão que recebeu evento, respeitando redução de movimento.

### Hover/foco e inspector

- Popover de duas colunas ou seções curtas: **Sessão** (status, ferramenta, modelo, host), **Tokens/contexto** (usado, janela, total), **Máquina** (CPU/RAM), **Origem** (fonte e hora). Omitir linhas de métricas ausentes ou explicar uma única vez por seção.
- Popover abre por hover e foco de teclado, fecha ao arrastar, e não impede iniciar o drag. Fonte e horário ficam associados ao valor, especialmente em host remoto.
- Inspector do selecionado: título, estado, função editável; depois métricas e conexões por **nome e direção**; por fim ações. “Abrir terminal” é ação principal, compactação/handoff aparecem com motivo quando aplicáveis. Remover vínculo é ação secundária identificável.

## Padrões de cor e acessibilidade

- Trabalhando: verde + círculo sólido. Aguardando: azul/âmbar suave + círculo vazado. Ocioso: neutro + círculo aberto. Encerrado: cinza + símbolo de parada. Host desconectado: alerta âmbar e texto explícito no card.
- Reservar vermelho para erro real. A porcentagem de contexto deve ter texto numérico além da barra; a sugestão de compactar não deve depender de cor.
- Área clicável do card permanece grande; controles pequenos têm alvo mínimo de 32–40 px. Navegação por teclado: Tab entre cards e controles, Enter seleciona, ação explícita ou duplo clique abre terminal.
- Usar tokens de `context.colors` e tipografia existentes. Novas frases passam pelo `slang` nos idiomas en/pt-BR/es.

## Sequência de implementação sugerida

1. Aplicar a correção de desempenho do arrasto e medir novamente em workspace complexo.
2. Separar desenho do card da telemetria e padronizar estado, contexto e alertas. O card pode usar dados já em cache; não deve iniciar nova coleta durante cada delta do arrasto.
3. Adicionar legenda e diferenciar três tipos de linha. Manter o painter isolado para que mover um card não reconstrua a barra e o inspector.
4. Reorganizar popover e inspector; então validar em 100%, 75% e 50% de zoom com workspace complexo, em tema claro/escuro e com teclado.

## Critério de aceitação visual

- Em até 3 segundos, o usuário identifica um terminal trabalhando, um aguardando, um contexto alto e um subagente temporário.
- Planejado, observado e subagente são distinguíveis sem hover.
- O nome e a direção das conexões são legíveis no inspector.
- Arrastar não altera vínculo nem exibe telemetria defasada como se fosse atual.
- Cards não ficam ilegíveis nos níveis usuais de zoom; o inspector não encobre permanentemente o card selecionado.
