# SCRIPT DE COMPILAÇÃO DE BASES EM ARQUIVOS .rds E .csv

# garanta que tenha instalado "bibliometrix", "writexl", "ggplot2", "htmlwidgets",
# "dplyr", "tidyr", "ineq"

options(repos = c(CRAN = "https://cloud.r-project.org"))
pacotes <- c("bibliometrix", "writexl", "ggplot2", "htmlwidgets",
             "dplyr", "tidyr", "ineq")
faltando <- pacotes[!pacotes %in% rownames(installed.packages())]
if (length(faltando) > 0) {
  message("Instalando pacotes que faltam: ", paste(faltando, collapse = ", "))
  install.packages(faltando, quiet = TRUE)
}
library(bibliometrix)

# ============================================================================
# PARÂMETROS DO USUÁRIO
# ============================================================================

# Filtro por tipo de documento. Mantenha FALSE para preservar o corpus
# completo. Se TRUE, mantém apenas os tipos que casam com TIPOS_MANTIDOS
# (editoriais, resenhas de livro, errata e correções costumam não ter
# author keywords e informa o % de dados ausentes).
FILTRAR_TIPOS  <- FALSE
TIPOS_MANTIDOS <- "^(ARTICLE|REVIEW|SHORT SURVEY|CONFERENCE PAPER)"

# ============================================================================
# FUNÇÕES AUXILIARES GERAIS - não mexer
# ============================================================================

# Escolher ARQUIVO via janela (RStudio -> tcltk -> console)
escolher_arquivo <- function(titulo, obrigatorio = TRUE) {
  message("\n>>> ", titulo)
  caminho <- NULL
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    caminho <- rstudioapi::selectFile(caption = titulo)
  } else if (capabilities("tcltk")) {
    caminho <- tcltk::tk_choose.files(caption = titulo, multi = FALSE)
    if (length(caminho) == 0) caminho <- NULL
  } else {
    caminho <- readline(paste0(titulo, " (digite o caminho, ou Enter para pular): "))
    if (caminho == "") caminho <- NULL
  }
  if (is.null(caminho) || length(caminho) == 0 || is.na(caminho) || caminho == "") {
    if (obrigatorio)
      stop("Nenhum arquivo selecionado. Rode o script novamente.", call. = FALSE)
    return(NULL)
  }
  caminho
}

# Escolher PASTA via janela (RStudio -> tcltk -> console)
escolher_pasta <- function(titulo = "Selecione a pasta") {
  message("\n>>> ", titulo)
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    pasta <- rstudioapi::selectDirectory(caption = titulo)
  } else if (capabilities("tcltk")) {
    pasta <- tcltk::tk_choose.dir(caption = titulo)
  } else {
    pasta <- readline(paste0(titulo, " (digite o caminho): "))
  }
  if (is.null(pasta) || is.na(pasta) || pasta == "") {
    stop("Nenhuma pasta selecionada. Operação cancelada.", call. = FALSE)
  }
  pasta
}

titulo_bloco <- function(t) {
  cat("\n============================================================\n",
      t, "\n============================================================\n", sep = "")
}

# Preparar data frame para CSV (resolve colunas do tipo list)
to_csv_safe <- function(x) {
  x <- as.data.frame(x, stringsAsFactors = FALSE, check.names = FALSE)
  x[] <- lapply(x, function(coluna) {
    if (is.list(coluna)) {
      sapply(coluna, function(v) {
        if (is.null(v) || length(v) == 0) return(NA_character_)
        paste(as.character(v), collapse = "; ")
      })
    } else coluna
  })
  x
}

# Salvar CSV em UTF-8 COM BOM (acentos corretos no Excel, inclusive Mac)
salvar_csv_excel <- function(df, caminho) {
  con <- file(caminho, open = "wb")
  writeBin(charToRaw("\xEF\xBB\xBF"), con)
  close(con)
  suppressWarnings(write.table(df, file = caminho, append = TRUE, sep = ",",
                               row.names = FALSE, col.names = TRUE,
                               qmethod = "double", fileEncoding = "UTF-8"))
}

# ============================================================================
# FUNÇÕES DA COMPILAÇÃO (dedup sem perda de dados) - não mexer
# ============================================================================

contar_referencias <- function(cr) {
  cr <- as.character(cr)
  cr[is.na(cr) | trimws(cr) %in% c("", "NA")] <- ""
  vapply(strsplit(cr, ";", fixed = TRUE), function(x) {
    if (length(x) == 1L && !nzchar(trimws(x))) return(0L)
    sum(nzchar(trimws(x)))
  }, integer(1))
}

normalizar_doi <- function(x) {
  x <- tolower(trimws(as.character(x))); x[is.na(x)] <- ""
  x <- sub("^https?://(dx\\.)?doi\\.org/", "", x)
  x <- sub("^doi[[:space:]]*:[[:space:]]*", "", x)
  x <- gsub("[[:space:]]", "", x)
  x[x %in% c("na", "none")] <- ""
  x
}

normalizar_titulo <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT", sub = "")
  x <- gsub("[^[:alnum:]]+", " ", tolower(x))
  trimws(gsub("[[:space:]]+", " ", x))
}

# "NA" e "none" literais (produzidos pelo convert2df) também são vazio
celula_vazia <- function(v) {
  v <- trimws(as.character(v))
  is.na(v) | !nzchar(v) | v %in% c("NA", "none", "NA,0000,NA")
}

# Componentes conexos (union-find) sobre uma lista de chaves por registro.
# Torna a deduplicação transitiva: se A=B por DOI e B=C por título/ano,
# A, B e C caem no mesmo grupo. 
agrupar_por_chaves <- function(lista_chaves) {
  n <- length(lista_chaves)
  if (n == 0L) return(integer(0))
  pai <- seq_len(n)
  raiz <- function(a) {
    while (pai[a] != a) {
      pai[a] <<- pai[pai[a]]
      a <- pai[a]
    }
    a
  }
  unir <- function(a, b) {
    ra <- raiz(a); rb <- raiz(b)
    if (ra != rb) pai[ra] <<- rb
    invisible(NULL)
  }
  mapa <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_len(n)) {
    chaves <- lista_chaves[[i]]
    for (k in chaves) {
      if (is.na(k) || !nzchar(k)) next
      if (exists(k, envir = mapa, inherits = FALSE)) {
        unir(i, get(k, envir = mapa, inherits = FALSE))
      } else {
        assign(k, i, envir = mapa)
      }
    }
  }
  vapply(seq_len(n), raiz, integer(1))
}

# Chaves de um data frame: DOI normalizado e/ou título+ano normalizados
montar_chaves <- function(df, usar_titulo = TRUE) {
  doi <- normalizar_doi(df$DI)
  chave_doi <- ifelse(nzchar(doi), paste0("doi:", doi), "")
  if (isTRUE(usar_titulo)) {
    ti <- normalizar_titulo(df$TI)
    py <- trimws(as.character(df$PY)); py[is.na(py)] <- ""
    chave_ti <- ifelse(nzchar(ti) & nzchar(py), paste0("ti:", ti, "||", py), "")
  } else {
    chave_ti <- rep("", nrow(df))
  }
  lapply(seq_len(nrow(df)), function(i) c(chave_doi[i], chave_ti[i]))
}

consolidar_grupo <- function(grupo) {
  base <- grupo[1, , drop = FALSE]
  recuperados <- 0L
  if (nrow(grupo) > 1L) {
    colunas <- setdiff(names(grupo), c(".ordem", ".n_ref", ".n_campos", ".grupo"))
    for (col in colunas) {
      if (is.list(grupo[[col]])) next
      if (celula_vazia(base[[col]][1])) {
        candidatos <- grupo[[col]][-1]
        candidatos <- candidatos[!celula_vazia(candidatos)]
        if (length(candidatos) > 0L) {
          base[[col]] <- candidatos[1]
          recuperados <- recuperados + 1L
        }
      }
    }
  }
  attr(base, "recuperados") <- recuperados
  base
}

# Consolida cada componente conexo mantendo, como registro-base, aquele com
# mais referências citadas (desempate: mais campos preenchidos, depois ordem
# de entrada). Campos vazios do base são preenchidos com os dos descartados.
consolidar_por_grupo <- function(df, grupos) {
  df$.grupo <- grupos
  ordem <- order(df$.grupo, -df$.n_ref, -df$.n_campos, df$.ordem)
  df <- df[ordem, , drop = FALSE]
  tamanhos <- table(df$.grupo)
  unicos <- df[df$.grupo %in% names(tamanhos)[tamanhos == 1L], , drop = FALSE]
  dups   <- df[df$.grupo %in% names(tamanhos)[tamanhos > 1L], , drop = FALSE]
  recuperados_total <- 0L
  if (nrow(dups) > 0L) {
    partes <- split(dups, dups$.grupo)
    consolidados <- lapply(partes, function(g) {
      r <- consolidar_grupo(g)
      recuperados_total <<- recuperados_total + attr(r, "recuperados")
      r
    })
    resultado <- dplyr::bind_rows(c(list(unicos), consolidados))
  } else {
    resultado <- unicos
  }
  resultado$.grupo <- NULL
  attr(resultado, "campos_recuperados") <- recuperados_total
  resultado
}

unir_bases_priorizando_referencias <- function(WOS, SCOPUS) {
  n_wos <- if (is.null(WOS)) 0L else nrow(WOS)
  n_scopus <- if (is.null(SCOPUS)) 0L else nrow(SCOPUS)
  todos <- dplyr::bind_rows(WOS, SCOPUS)
  n_bruto <- nrow(todos)
  todos$.ordem <- seq_len(n_bruto)
  todos$.n_ref <- contar_referencias(todos$CR)
  campos <- intersect(c("AU", "TI", "SO", "PY", "DI", "AB", "DE", "ID", "C1", "RP"), names(todos))
  todos$.n_campos <- rowSums(vapply(todos[campos], function(x) {
    !celula_vazia(x)
  }, logical(n_bruto)))

  # Contagens para o PRISMA: quanto o DOI resolve sozinho, quanto título/ano acrescenta
  grupos_doi   <- agrupar_por_chaves(montar_chaves(todos, usar_titulo = FALSE))
  grupos_final <- agrupar_por_chaves(montar_chaves(todos, usar_titulo = TRUE))
  n_apos_doi <- length(unique(grupos_doi))

  todos <- consolidar_por_grupo(todos, grupos_final)
  recuperados <- attr(todos, "campos_recuperados")
  n_final <- nrow(todos)

  todos <- todos[order(todos$.ordem), , drop = FALSE]
  diagnostico <- data.frame(
    registros_wos = n_wos, registros_scopus = n_scopus,
    registros_identificados = n_bruto,
    duplicados_por_doi = n_bruto - n_apos_doi,
    duplicados_adicionais_titulo_ano = n_apos_doi - n_final,
    duplicados_removidos = n_bruto - n_final,
    campos_recuperados_de_duplicados = recuperados,
    documentos = n_final,
    documentos_com_CR = sum(todos$.n_ref > 0L),
    total_referencias = sum(todos$.n_ref)
  )
  todos$.ordem <- todos$.n_ref <- todos$.n_campos <- NULL

  # Normaliza DE/ID ANTES do mergeDbSources, que constrói KW_Merged
  for (kw in intersect(c("DE", "ID"), names(todos))) {
    v <- trimws(as.character(todos[[kw]]))
    v[is.na(v) | v %in% c("NA", "none")] <- ""
    todos[[kw]] <- v
  }

  resultado <- mergeDbSources(todos, remove.duplicated = FALSE, verbose = FALSE)
  if ("CR_raw" %in% names(resultado)) resultado$CR <- resultado$CR_raw
  attr(resultado, "diagnostico_CR") <- diagnostico
  resultado
}

imprimir_resumo_prisma <- function(base_final) {
  d <- attr(base_final, "diagnostico_CR")
  if (is.null(d)) return(invisible(NULL))
  sem_cr <- d$documentos - d$documentos_com_CR
  cobertura <- if (d$documentos > 0) 100 * d$documentos_com_CR / d$documentos else 0
  cat("\n============================================================\n",
      "RESUMO PARA O FLUXOGRAMA PRISMA\n",
      "============================================================\n",
      sprintf("Registros identificados na Web of Science: %d\n", d$registros_wos),
      sprintf("Registros identificados na Scopus:        %d\n", d$registros_scopus),
      sprintf("Total de registros identificados:         %d\n", d$registros_identificados),
      "------------------------------------------------------------\n",
      sprintf("Duplicados removidos por DOI:              %d\n", d$duplicados_por_doi),
      sprintf("Duplicados adicionais por titulo/ano:      %d\n", d$duplicados_adicionais_titulo_ano),
      sprintf("Total de duplicados removidos:             %d\n", d$duplicados_removidos),
      sprintf("Campos recuperados dos duplicados:         %d\n", d$campos_recuperados_de_duplicados),
      "  (campos vazios do registro mantido preenchidos com dados\n",
      "   do duplicado antes do descarte - nenhum dado perdido)\n",
      "------------------------------------------------------------\n",
      sprintf("Corpus final para triagem/analise:         %d\n", d$documentos),
      "------------------------------------------------------------\n",
      "INFORMACOES COMPLEMENTARES SOBRE REFERENCIAS CITADAS\n",
      sprintf("Documentos com referencias citadas:        %d\n", d$documentos_com_CR),
      sprintf("Documentos sem referencias citadas:        %d\n", sem_cr),
      sprintf("Cobertura de referencias citadas:          %.1f%%\n", cobertura),
      sprintf("Total de referencias citadas preservadas:  %d\n", d$total_referencias),
      "============================================================\n\n", sep = "")
  invisible(d)
}

# Completude dos metadados + composição por tipo de documento.
# Serve para saber se um % alto de keywords ausentes vem do corpus
# (editoriais, resenhas, errata) ou de falha na compilação.
imprimir_diagnostico_completude <- function(M) {
  titulo_bloco("COMPLETUDE DOS METADADOS (missingData)")
  res <- try(missingData(M), silent = TRUE)
  if (!inherits(res, "try-error")) print(res$mandatoryTags, row.names = FALSE)

  if ("DT" %in% names(M) && "DE" %in% names(M)) {
    sem_de <- celula_vazia(M$DE)
    cat("\nDocumentos SEM author keywords (DE), por tipo de documento:\n")
    tab <- sort(table(toupper(trimws(as.character(M$DT[sem_de])))), decreasing = TRUE)
    if (length(tab) > 0) {
      for (i in seq_along(tab)) cat(sprintf("   %5d  %s\n", tab[i], names(tab)[i]))
    }
    cat(sprintf("\nTotal sem DE: %d de %d (%.2f%%)\n",
                sum(sem_de), nrow(M), 100 * sum(sem_de) / nrow(M)))
    substantivos <- grepl(TIPOS_MANTIDOS, toupper(trimws(as.character(M$DT))))
    if (any(substantivos)) {
      cat(sprintf("Restringindo a %s: %d docs, %d sem DE (%.2f%%)\n",
                  TIPOS_MANTIDOS, sum(substantivos),
                  sum(sem_de & substantivos),
                  100 * sum(sem_de & substantivos) / sum(substantivos)))
    }
  }
  invisible(NULL)
}

remover_undefined <- function(celula) {
  if (is.na(celula) || celula == "") return(celula)
  itens <- unlist(strsplit(celula, ";", fixed = TRUE))
  itens <- trimws(itens)
  itens <- itens[itens != "" & !grepl("undefined", itens, ignore.case = TRUE)]
  if (length(itens) == 0) return("")
  paste(itens, collapse = "; ")
}

# ============================================================================
# OBTER O CORPUS (compilar dos brutos)
# ============================================================================

  # ---- Compilar a partir dos arquivos brutos ----
  titulo_bloco("COMPILAÇÃO DAS BASES (Scopus + WoS)")
  pasta_brutos <- escolher_pasta(
    "Selecione a pasta com os arquivos brutos (Scopus .csv e WoS .txt)")

  gerados <- file.path(pasta_brutos, c("final.csv", "final.txt"))

  arquivos_scopus <- setdiff(
    list.files(pasta_brutos, pattern = "\\.csv$",
               full.names = TRUE, ignore.case = TRUE), gerados)
  arquivos_wos <- setdiff(
    list.files(pasta_brutos, pattern = "\\.txt$",
               full.names = TRUE, ignore.case = TRUE), gerados)

  cat("\nArquivos encontrados na pasta:\n")
  cat(sprintf("  Scopus (.csv): %d\n", length(arquivos_scopus)))
  if (length(arquivos_scopus) > 0) cat(paste0("    - ", basename(arquivos_scopus), "\n"), sep = "")
  cat(sprintf("  WoS (.txt):    %d\n", length(arquivos_wos)))
  if (length(arquivos_wos) > 0) cat(paste0("    - ", basename(arquivos_wos), "\n"), sep = "")

  if (length(arquivos_scopus) == 0 && length(arquivos_wos) == 0) {
    stop("Nenhum arquivo .csv (Scopus) ou .txt (WoS) encontrado na pasta selecionada.")
  }

  SCOPUS <- NULL
  if (length(arquivos_scopus) > 0) {
    SCOPUS <- convert2df(file = arquivos_scopus, dbsource = "scopus", format = "csv")
  }
  WOS <- NULL
  if (length(arquivos_wos) > 0) {
    WOS <- convert2df(file = arquivos_wos, dbsource = "wos", format = "plaintext")
  }

  FINAL <- unir_bases_priorizando_referencias(WOS, SCOPUS)

  # Tratamentos da base (CR, keywords, "undefined")
  if ("CR_raw" %in% colnames(FINAL)) {
    cr_vazio <- is.na(FINAL$CR) | trimws(FINAL$CR) %in% c("", "NA")
    FINAL$CR[cr_vazio] <- FINAL$CR_raw[cr_vazio]
    FINAL$CR <- gsub("\n", ";", FINAL$CR)
  }
  FINAL$DE <- trimws(as.character(FINAL$DE)); FINAL$DE[is.na(FINAL$DE)] <- ""
  FINAL$ID <- trimws(as.character(FINAL$ID)); FINAL$ID[is.na(FINAL$ID)] <- ""
  FINAL$CR <- vapply(FINAL$CR, remover_undefined, character(1), USE.NAMES = FALSE)
  if ("CR_raw" %in% colnames(FINAL)) {
    FINAL$CR_raw <- vapply(FINAL$CR_raw, remover_undefined, character(1), USE.NAMES = FALSE)
  }

  # [5] Filtro opcional por tipo de documento (padrão: desligado)
  if (isTRUE(FILTRAR_TIPOS) && "DT" %in% names(FINAL)) {
    manter <- grepl(TIPOS_MANTIDOS, toupper(trimws(as.character(FINAL$DT))))
    cat(sprintf("\nFiltro de tipo de documento ATIVO (%s)\n", TIPOS_MANTIDOS))
    cat(sprintf("  Documentos antes:  %d\n  Documentos depois: %d\n  Removidos:         %d\n",
                nrow(FINAL), sum(manter), nrow(FINAL) - sum(manter)))
    atributo <- attr(FINAL, "diagnostico_CR")
    FINAL <- FINAL[manter, , drop = FALSE]
    attr(FINAL, "diagnostico_CR") <- atributo
  }

  # Salvar final.rds e final.csv na própria pasta dos brutos
  saveRDS(FINAL, file.path(pasta_brutos, "final.rds"))
  salvar_csv_excel(to_csv_safe(FINAL), file.path(pasta_brutos, "final.csv"))
  cat(sprintf("\nArquivos salvos:\n  %s\n  %s\n",
              file.path(pasta_brutos, "final.rds"),
              file.path(pasta_brutos, "final.csv")))

  imprimir_resumo_prisma(FINAL)
  imprimir_diagnostico_completude(FINAL)


# O script chegou ao fim e os arquivos estão na pasta. 
# Esse código foi desenvolvido pela Profa. Dra. Larissa Raposo - lararaposo@gmail.com para fins acadêmicos e de uso pessoal.
# Fique à vontade para evoluí-lo!
# Para citar o uso do script: Raposo, L. (2026). Bibliometria: scripts em R para análise bibliométrica com bibliometrix (Versão 1) [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.21959591

# Agora, siga com o Biblioshiny para as suas análises.Boa sorte.

biblioshiny()
