# Benchmark do grafo com perfil instalado (Windows, 2026-10-03)

## Cenário e método

- Build `flutter run --profile -d windows --no-pub`, Impeller OpenGL ES, janela maximizada em 3456 × 1408 pixels.
- O estado instalado tinha 11 layouts e 26 sessões salvas; o maior layout tinha 11 sessões (10 terminais e um viewer).
- A instância profile foi iniciada enquanto havia outra instância debug ativa, vinda de outro checkout.
- A timeline foi coletada pelo Dart VM Service com `live_timeline_probe.dart`, sem coletar conteúdo dos terminais.
- CPU foi medido como tempo de CPU do processo durante 10 segundos, expresso em porcentagem de um núcleo. Memória é o working set do processo.

## Resultados observados

| Condição | Frames na janela | Tempo de frame | CPU / núcleo | Working set |
|---|---:|---|---:|---:|
| Terminais, 10 s sem eventos de ponteiro | 0 | Sem frame solicitado | 3,3% | 286,7 MiB |
| Grafo aberto, 10 s com 1.430 pacotes de ponteiro | 126 | p50 5,14 ms; p95 8,15 ms; máximo 12,05 ms; 0 acima de 16,67 ms | 66,7% | 259,2 MiB |
| Grafo em segundo plano, 10 s com 484 pacotes de ponteiro | 10 | p50 1,01 ms; p95 2,56 ms; 0 acima de 16,67 ms | 17,2% | 282,8 MiB |

Um arrasto do fundo do grafo gerou 17 frames durante a janela de captura de 8 segundos. Essa contagem não é uma taxa de quadros do gesto: a janela inclui tempo antes e depois do arrasto.

Os números de CPU das três linhas **não são uma comparação controlada**. Houve movimento do ponteiro e atividade simultânea da outra instância. O tempo de frame mostra que os frames capturados nessa janela ficaram abaixo do orçamento de 16,67 ms; não demonstra fluidez sustentada a 60 fps.

## Falha encontrada e correção

O primeiro clique no botão do grafo gerou `context.read<ProcessMetricsProvider>(): no scoped ProcessMetricsProvider provided`. O provedor estava registrado no módulo, mas `context.read` busca um registro no escopo da rota. Ele foi movido para `Scoped.add` no `provide` da rota. Após recompilar, o grafo abriu no workspace real sem a exceção. O analyzer dos arquivos alterados concluiu sem problemas.

## Estado do perfil após a execução

O layout mais complexo foi regravado com 8 sessões após a restauração dos terminais, contra 11 na inspeção anterior à execução. Uma referência do perfil debug contém 11 sessões nesse mesmo layout. A comparação por ID encontrou 7 sessões comuns, 4 presentes apenas na referência debug (3 terminais e um viewer) e 1 terminal presente apenas no estado profile atual.

O arquivo `build/bench/layouts-merged-candidate.json` é uma proposta **não aplicada**: mantém o layout profile atual e adiciona as 4 sessões e suas abas da referência debug. Ele teria 12 sessões nesse layout, 27 ao todo nos 11 layouts. A verificação encontrou zero abas sem descriptor. Os snapshots `layouts-profile-after.json` e `layouts-debug-reference.json` estão na mesma pasta ignorada pelo Git. Nenhum desses arquivos deve ser publicado: contêm estado local do usuário.

A revisão automática bloqueou o fechamento da instância profile devido ao risco de consolidar a perda de sessões. A instância segue aberta e o arquivo instalado recebeu novas escritas após o snapshot; a proposta precisa ser recalculada a partir do estado final antes de qualquer recuperação autorizada.

O benchmark completo do layout original de 11 sessões e a medição controlada de abertura, drag de box e zoom continuam pendentes até resolver a recuperação do perfil e a concorrência com a outra instância.

## Correção posterior à captura

Depois da captura acima, o arrasto de um box passou a atualizar somente a posição visual em memória durante o gesto. A posição é gravada no modelo do workspace uma vez, ao soltar o mouse ou cancelar o gesto. O layout inicial das abas ainda sem box salvo também é mantido em cache, e o desenho dos cards e das conexões foi isolado em limites de pintura. Esses ajustes **não estão incluídos nos números da tabela**; não há medição posterior no perfil instalado enquanto a recuperação das sessões e o fechamento da instância profile seguem pendentes.

Validação após a alteração: análise estática do widget sem problemas, traduções geradas e quatro testes de domínio do grafo aprovados. Isso verifica contratos e compilação, mas não substitui a medição de arrasto no app atualizado.
