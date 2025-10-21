library(pdftools)
library(dplyr)
library(tidytext)
library(textdata)
library(ggplot2)
library(lubridate)
library(httr)
library(jsonlite)
library(tidyr)
library(wordcloud)
library(RColorBrewer)
library(stringr)

# 2. Carregar o dicionário Loughran-McDonald
loughran_mcdonald <- lexicon_loughran()

# 3. Função robusta para baixar e extrair texto de PDF
baixar_pdf_texto_robusto <- function(url) {
  if (is.na(url) || url == "") return(NA_character_)
  
  parsed <- httr::parse_url(url)
  parsed$path <- gsub(" ", "%20", parsed$path, fixed = TRUE)
  url_enc <- httr::build_url(parsed)
  
  tmp <- tempfile(fileext = ".pdf")
  resp <- tryCatch(
    httr::GET(url_enc,
              httr::user_agent("Mozilla/5.0 (R; +https://www.r-project.org/)"),
              httr::timeout(30)),
    error = function(e) e
  )
  
  if (inherits(resp, "error")) {
    message(sprintf("ERRO (GET): %s -> %s", url, resp$message))
    return(NA_character_)
  }
  
  if (httr::status_code(resp) != 200) {
    message(sprintf("Status !=200 (%s) para: %s", httr::status_code(resp), url))
    return(NA_character_)
  }
  
  bin <- tryCatch(httr::content(resp, as = "raw"), error = function(e) e)
  if (inherits(bin, "error") || length(bin) == 0) {
    message(sprintf("Não conseguiu obter conteúdo binário: %s", url))
    return(NA_character_)
  }
  
  tryCatch({
    writeBin(bin, tmp)
    texto <- pdftools::pdf_text(tmp) %>% paste(collapse = "\n")
    unlink(tmp)
    return(texto)
  }, error = function(e) {
    message(sprintf("Falha ao ler PDF: %s -> %s", url, e$message))
    if (file.exists(tmp)) unlink(tmp)
    return(NA_character_)
  })
}

# 4. Baixar e pré-processar as atas do COPOM
raw_copom <- fromJSON(
  "https://www.bcb.gov.br/api/servico/sitebcb/copomminutes/ultimas?quantidade=2000&filtro="
)$conteudo %>%
  as_tibble() %>%
  select(meeting = Titulo, url = Url) %>%
  mutate(url = paste0("https://www.bcb.gov.br", url))

# Extrair o número da reunião para ordenação correta
raw_copom <- raw_copom %>%
  mutate(meeting_number = as.numeric(gsub("\\D", "", meeting)))

# Limitar às últimas 25 atas (ordenando pelo número da reunião em ordem decrescente)
raw_copom <- raw_copom %>%
  arrange(desc(meeting_number)) %>%
  head(25)

# Baixar e extrair texto de cada ata
minutes_data <- raw_copom %>%
  mutate(text = sapply(url, baixar_pdf_texto_robusto)) %>%
  filter(!is.na(text))

# Pré-processamento (limpeza, tokenização)
minutes_data$text <- gsub("\\n", " ", minutes_data$text)
minutes_data$text <- gsub("\\s+", " ", minutes_data$text) 
minutes_data$text <- tolower(minutes_data$text) 

# Tokenização
tokenized_minutes <- minutes_data %>%
  unnest_tokens(word, text)

# Remover stop words
stop_words_english <- get_stopwords("en") 
tokenized_minutes <- tokenized_minutes %>%
  anti_join(stop_words_english, by = "word")

# Análise de Sentimento com múltiplos tipos
sentiment_scores <- tokenized_minutes %>%
  inner_join(loughran_mcdonald, by = "word") %>%
  count(meeting, sentiment) %>%
  pivot_wider(names_from = sentiment, values_from = n, values_fill = 0)

# Garantir que todas as colunas de sentimento existam
sentiment_cols <- c("positive", "negative", "uncertainty", "litigious", "constraining")
for (col in sentiment_cols) {
  if (!col %in% colnames(sentiment_scores)) sentiment_scores[[col]] <- 0
}

# Extrair datas dos títulos das atas
minutes_data <- minutes_data %>%
  mutate(date_str = str_extract(meeting, "\\w+ \\d{1,2}-\\d{1,2}, \\d{4}|\\w+ \\d{1,2}, \\d{4}"),
         date = parse_date_time(date_str, orders = c("mdy", "mdY")))

# Extrair a taxa Selic diretamente do texto das atas
extract_selic_rate <- function(text) {
  # Padrões comuns para encontrar a taxa Selic no texto
  patterns <- c(
    "selic rate (?:at|to) (\\d+\\.+\\d+)%",
    "target for the selic rate (?:at|to) (\\d+\\.+\\d+)%",
    "selic rate of (\\d+\\.+\\d+)%",
    "selic (?:at|to) (\\d+\\.+\\d+)%",
    "basic interest rate (?:at|to) (\\d+\\.+\\d+)%",
    "rate (?:at|to) (\\d+\\.+\\d+)% per annum",
    "to (\\d+\\.+\\d+)% p\\.a\\."
  )
  
  for (pattern in patterns) {
    match <- regmatches(text, regexpr(pattern, text, ignore.case = TRUE))
    if (length(match) > 0) {
      rate <- as.numeric(gsub(".*?(\\d+\\.+\\d+)%.*", "\\1", match))
      if (!is.na(rate)) {
        return(rate)
      }
    }
  }
  
  return(NA_real_)
}

# Aplicar a extração da taxa Selic para cada ata
minutes_data <- minutes_data %>%
  mutate(selic_rate = sapply(text, extract_selic_rate))

# Extrair datas dos títulos das atas (ex: "272nd Meeting - July 29-30, 2025" -> 2025-07-30)
minutes_data$date <- minutes_data$meeting %>%
  gsub(".*\\s+(\\w+)\\s+(\\d{1,2})\\-?(\\d{1,2})?,\\s*(\\d{4}).*", "\\1 \\2 \\4", .) %>%
  parse_date_time(orders = c("mdy", "mY"))

# Se a extração da data falhar para algumas, tentar um padrão alternativo
minutes_data$date[is.na(minutes_data$date)] <- minutes_data$meeting[is.na(minutes_data$date)] %>%
  gsub(".*\\s+(\\w+)\\s+(\\d{4}).*", "\\1 \\2", .) %>%
  parse_date_time(orders = c("mY"))

# Juntar as pontuações de sentimento com os dados da Selic
analysis_data <- sentiment_scores %>%
  left_join(minutes_data %>% select(meeting, date, selic_rate), by = "meeting")

# Calcular net_sentiment
analysis_data <- analysis_data %>%
  mutate(net_sentiment = positive - negative)

# Nuvem de Palavras
# Calcular a frequência das palavras (excluindo stop words já removidas)
word_freq <- tokenized_minutes %>%
  count(word, sort = TRUE) %>%
  filter(n > 30)  # Filtrar palavras com mais de 5 ocorrências para evitar ruído

# Gerar a nuvem de palavras
set.seed(123)  # Para reprodutibilidade
wordcloud(words = word_freq$word,
          freq = word_freq$n,
          min.freq = 30,  # Mínimo de ocorrências
          max.words = 100,  # Máximo de palavras na nuvem
          random.order = FALSE,  # Ordenar por frequência
          colors = brewer.pal(8, "Dark2"),  # Paleta de cores
          scale = c(4, 0.5),  # Ajusta o tamanho das palavras
          rot.per = 0.2)  # 20% das palavras rotacionadas

# Visualizações
# Gráfico de Linha: Sentimento Líquido vs. Taxa Selic
ggplot(analysis_data, aes(x = date)) +
  geom_line(aes(y = net_sentiment, color = "Sentimento Líquido")) +
  geom_line(aes(y = selic_rate, color = "Taxa Selic")) +
  labs(title = "Sentimento Líquido vs. Taxa Selic",
       x = "Data", y = "Valor") +
  scale_color_manual(values = c("Sentimento Líquido" = "blue", "Taxa Selic" = "red")) +
  theme_minimal()

# Gráfico de Dispersão: Sentimento Líquido vs. Taxa Selic
ggplot(analysis_data, aes(x = net_sentiment, y = selic_rate)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE, color = "blue") +
  labs(title = "Dispersão: Sentimento Líquido vs. Taxa Selic",
       x = "Sentimento Líquido", y = "Taxa Selic") +
  theme_minimal()

# Gráfico de Análise de Sentimentos (Barras Empilhadas por Tipo de Sentimento)
sentiment_long <- analysis_data %>%
  select(meeting, date, positive, negative, uncertainty, litigious, constraining) %>%
  pivot_longer(cols = c(positive, negative, uncertainty, litigious, constraining),
               names_to = "sentiment_type",
               values_to = "score") %>%
  mutate(sentiment_type = factor(sentiment_type, levels = c("positive", "negative", "uncertainty", "litigious", "constraining")))

ggplot(sentiment_long, aes(x = reorder(meeting, date), y = score, fill = sentiment_type)) +
  geom_bar(stat = "identity") +
  coord_flip() +
  labs(title = "Distribuição de Sentiment Scores por Reunião do COPOM",
       x = "Reunião", y = "Contagem de Palavras") +
  scale_fill_brewer(palette = "Set3", name = "Tipo de Sentimento") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8),
        plot.title = element_text(hjust = 0.5, size = 14),
        legend.position = "top")

# Gráfico de Análise de Sentimentos (Barras por Reunião)
ggplot(analysis_data, aes(x = reorder(meeting, date), y = net_sentiment, fill = net_sentiment > 0)) +
  geom_bar(stat = "identity") +
  coord_flip() +
  labs(title = "Análise de Sentimento Líquido por Reunião do COPOM",
       x = "Reunião", y = "Sentimento Líquido (Negativo ← Positivo)") +
  scale_fill_manual(values = c("TRUE" = "green", "FALSE" = "red"),
                    labels = c("Negativo", "Positivo"),
                    name = "Sentimento") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8),
        plot.title = element_text(hjust = 0.5, size = 14),
        legend.position = "top")

# Correlação
cor(analysis_data$net_sentiment, analysis_data$selic_rate, use = "complete.obs")
