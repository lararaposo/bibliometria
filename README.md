# bibliometria

[![DOI](https://zenodo.org/badge/1335457929.svg)](https://doi.org/10.5281/zenodo.21959591)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![R](https://img.shields.io/badge/R-%E2%89%A5%204.1-blue.svg)](https://www.r-project.org/)

Scripts em R para análise bibliométrica com o pacote [`bibliometrix`](https://github.com/massimoaria/bibliometrix).

---

## Conteúdo do repositório

| Arquivo | Função |
|---|---|
| `script_integracao_de_bases.R` | Compila, deduplica e consolida exportações da Web of Science e da Scopus em um corpus único, com resumo PRISMA e diagnóstico de completude |

---

## `script_integracao_de_bases.R`

Reúne exportações da **Web of Science** e da **Scopus** em um único corpus pronto para análise no `bibliometrix` / `biblioshiny`.

A deduplicação é feita **sem perda de metadados**: quando um mesmo documento aparece nas duas bases, o registro mantido é o mais completo em referências citadas, e seus campos vazios são preenchidos com os dados do registro descartado antes do descarte. O script também emite um resumo pronto para o fluxograma PRISMA e um diagnóstico de completude dos metadados.

### Por que este script

O `mergeDbSources()` do `bibliometrix` remove duplicados pela regra "primeiro que aparece vence", descartando o registro redundante por inteiro. Quando WoS e Scopus se complementam — e elas se complementam com frequência, sobretudo em *abstract*, *author keywords* e *cited references* — isso significa perder metadados recuperáveis.

Este script substitui essa etapa por:

1. **Agrupamento transitivo por componentes conexos** (union-find) sobre duas chaves na mesma passada: DOI normalizado e título+ano normalizados. Deduplicação em passadas independentes não fecha encadeamentos do tipo A≡B por DOI e B≡C por título; esta abordagem fecha.
2. **Escolha do registro-base** por número de referências citadas (desempate: número de campos preenchidos, depois ordem de entrada).
3. **Consolidação campo a campo**: toda célula vazia do registro-base é preenchida a partir dos duplicados do mesmo grupo. O total de campos recuperados é reportado.

---

## Requisitos

- R ≥ 4.1
- Pacotes: `bibliometrix`, `dplyr`, `tidyr`, `writexl`, `ggplot2`, `htmlwidgets`, `ineq`
- `rstudioapi` (opcional — usado para as janelas de seleção de pasta no RStudio; sem ele o script recorre ao `tcltk` e, na falta deste, ao console)

O bloco inicial instala automaticamente o que estiver faltando.

---

## Exportando os arquivos brutos

**Web of Science** → `Export` → `Plain text file` → *Record Content*: **Full Record and Cited References** → salvar como `.txt`.
Exportações são limitadas a 500 registros por arquivo; gere quantos arquivos forem necessários e coloque todos na mesma pasta.

**Scopus** → `Export` → `CSV` → marcar **todos** os grupos de campos, em especial *Abstract & keywords* e *References*.
Sem *References* marcado, o campo `CR` vem vazio e nenhuma análise de cocitação ou acoplamento bibliográfico é possível.

Coloque todos os `.txt` (WoS) e `.csv` (Scopus) em **uma única pasta**, sem nenhum outro arquivo desses formatos.

---

## Uso

```r
source("script_integracao_de_bases.R")
```

O script abre uma janela para você selecionar a pasta com os arquivos brutos, processa tudo e grava os resultados na mesma pasta. Ao final, o `biblioshiny()` é aberto automaticamente — carregue nele o `final.rds` gerado.

### Parâmetro opcional

No topo do script:

```r
FILTRAR_TIPOS  <- FALSE
TIPOS_MANTIDOS <- "^(ARTICLE|REVIEW|SHORT SURVEY|CONFERENCE PAPER)"
```

Com `FILTRAR_TIPOS <- TRUE`, o corpus final retém apenas os tipos de documento que casam com a expressão regular. Editoriais, resenhas de livro, errata, correções e itens biográficos raramente têm *author keywords* e inflam artificialmente o percentual de metadados ausentes.

Esta é uma decisão **metodológica**, não técnica: o filtro se justifica quando esses documentos não são unidades de análise do estudo — não quando o objetivo é melhorar o indicador de completude.

---

## Saídas

| Arquivo | Conteúdo |
|---|---|
| `final.rds` | Objeto `bibliometrixDB` — é este que se carrega no `biblioshiny` |
| `final.csv` | Mesmo corpus em CSV UTF-8 **com BOM** (acentuação correta no Excel, inclusive no macOS) |

E, no console, três blocos:

**1. Resumo PRISMA** — registros identificados por base, duplicados removidos por DOI, duplicados adicionais por título/ano, campos recuperados dos duplicados e corpus final. Números prontos para transcrever no fluxograma.

**2. Cobertura de referências citadas** — quantos documentos têm `CR` preenchido e o total de referências preservadas.

**3. Completude dos metadados** — saída do `missingData()` do `bibliometrix` mais a composição, por tipo de documento, dos registros sem *author keywords*. Serve para distinguir uma falha de compilação de uma característica do corpus.

### Exemplo de saída

Corpus de marketing e comportamento do consumidor, 1.378 registros WoS + 1.272 Scopus:

```
Total de registros identificados:         2650
Duplicados removidos por DOI:             1251
Duplicados adicionais por titulo/ano:        9
Campos recuperados dos duplicados:        1150
Corpus final para triagem/analise:        1390

DE (Keywords)      ausente em 257 (18,49%)
ID (Keywords Plus) ausente em 209 (15,04%)
AB (Abstract)      ausente em  83  (5,97%)
```

Dos 257 documentos sem *author keywords*, 176 (68%) eram *Editorial Material*, *Book Review*, *Correction*, *Erratum* ou itens biográficos — documentos que genuinamente não recebem palavras-chave em nenhuma das duas bases. Restringindo a *Article* + *Review*, a ausência cai para 6,29%.

---

## Notas metodológicas

**Sobre `CR` e `CR_raw`.** Quando o corpus reúne mais de uma base, o `mergeDbSources()` renomeia `CR` para `CR_raw` e preenche `CR` com `"NA"`. O script restaura `CR` a partir de `CR_raw` e remove entradas `undefined` — artefatos comuns nas referências exportadas pela Scopus — antes de gravar.

**Sobre células "vazias".** O `convert2df()` grava strings literais `"NA"` e `"none"` em campos ausentes. O script trata essas strings como vazias tanto na recuperação de campos quanto na contagem de completude, alinhando-se ao critério do `missingData()`.

**Sobre `Index Keywords` da Scopus.** Em áreas de negócios e ciências sociais aplicadas, a Scopus raramente atribui *index keywords* (que dependem de tesauros usados sobretudo em STM). Se o seu corpus é dessas áreas, espere que o campo `ID` (*Keywords Plus*) venha exclusivamente da WoS — vale verificar antes de planejar análises que dependam dele.

**Sobre a sobreposição entre bases.** O resumo PRISMA permite calcular quantos documentos são exclusivos de cada base. Uma sobreposição muito alta é um resultado relevante em si e merece ser reportada na seção de método.

---

## Limitações conhecidas

- O casamento por título+ano usa normalização agressiva (remoção de acentos, pontuação e caixa). Títulos genéricos e curtos publicados no mesmo ano podem, em tese, colidir.
- Não há tratamento para DOIs incorretos na fonte: dois documentos distintos com o mesmo DOI registrado erroneamente serão fundidos.
- Testado com exportações WoS em *plain text* e Scopus em CSV. Outras bases (Lens, Dimensions, OpenAlex) exigiriam adaptação da leitura, embora a lógica de consolidação seja agnóstica à origem.

---

## Como citar

Este repositório está arquivado no Zenodo e possui DOI permanente.

**APA 7:**

> Raposo, L. (2026). *bibliometria: scripts em R para análise bibliométrica com bibliometrix* (Versão 1) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.21959591

**BibTeX:**

```bibtex
@software{raposo_bibliometria_2026,
  author    = {Raposo, Larissa},
  title     = {bibliometria: scripts em R para análise bibliométrica com bibliometrix},
  year      = {2026},
  version   = {v1},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.21959591},
  url       = {https://github.com/lararaposo/bibliometria}
}
```

O DOI `10.5281/zenodo.21959591` é o **DOI de conceito**: aponta sempre para a versão mais recente. Para citar uma versão específica, use o DOI daquela versão (v1: `10.5281/zenodo.21959592`).

O arquivo `CITATION.cff` na raiz do repositório alimenta o botão **"Cite this repository"** do GitHub.

---

## Licença

[MIT](LICENSE) — uso, modificação e redistribuição livres, inclusive comercial, mantido o aviso de autoria.

Observação: o `bibliometrix`, do qual estes scripts dependem, é licenciado sob GPL-3. Os scripts deste repositório não incorporam código do pacote; apenas o invocam.

---

## Autoria e contribuições

Desenvolvido por **Prof.ª Dr.ª Larissa Raposo** (ESPM) para fins acadêmicos.

*Issues*, *pull requests* e *forks* são bem-vindos. Se você usar os scripts em um trabalho publicado, a citação acima é a forma mais útil de retorno.
