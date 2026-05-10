# ====================================================
# Script: 11_complete_processed_log.R

# Purpose: Group all processed file logs into one master log
#          Check for duplicates, remove test files, and remove overlapped processing

# Author:  Dane Tipene
# Last updated: 2026-05-06
# ====================================================


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ SharePoint Configuration --------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Replace these values with your organisation's SharePoint details
sharepoint_site_url  <- "https://your-organisation.sharepoint.com/teams/your-team"
drive_name           <- "Documents"
sharepoint_base_path <- "path/to/your/transcription/folder"


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Load Libraries ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

stitch_packages <- c("arrow", "dplyr", "here", "Microsoft365R", "officer", 
                     "purrr", "readr", "stringr")

for (pkg in stitch_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  library(pkg, character.only = TRUE)
}


# ──────────────────────────────────────────────────────────────────────────────
# 3️⃣ Connect to SharePoint -----------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("=== Connecting to SharePoint ===\n\n")

site  <- get_sharepoint_site(site_url = sharepoint_site_url)
drive <- site$get_drive(drive_name)

# List all CSV logs in the base path
files    <- drive$list_items(sharepoint_base_path)
files_df <- bind_rows(files)

log_files <- files_df %>%
  filter(str_detect(name, "\\.csv$"))

# Download and bind all logs
logs <- lapply(log_files$name, function(f) {
  log_path <- paste0(sharepoint_base_path, "/", f)
  temp     <- tempfile(fileext = ".csv")
  drive$download_file(log_path, dest = temp, overwrite = TRUE)
  read.csv(temp, stringsAsFactors = FALSE)
})

master_log <- bind_rows(logs)


# ──────────────────────────────────────────────────────────────────────────────
# 4️⃣ Data Wrangling ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Remove test files
temp_df <- master_log %>%
  filter(!file_name %in% c("01_jfk.flac", "02_jfk.flac"))

# Explore duplicate rows
duplicates <- temp_df[duplicated(temp_df), ]

cat(paste0("=== Duplicate Count: ", nrow(duplicates), " ===\n\n"))

# Get counts for analysts processing
analyst_counts <- temp_df %>% 
  group_by(analyst) %>% 
  summarise(count = n()) %>% 
  arrange(desc(count))

# Add 'TOTAL' row
analyst_counts <- analyst_counts %>% 
  bind_rows(tibble(analyst = "TOTAL", count = sum(analyst_counts$count)))

total_files_processed <- nrow(temp_df)


# ──────────────────────────────────────────────────────────────────────────────
# 5️⃣ Save Outputs --------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Write feather
dir.create(here("01_Scripts/Feathers"), showWarnings = FALSE, recursive = TRUE)
write_feather(temp_df, here("01_Scripts/Feathers/master_log.feather"))
write_feather(analyst_counts, here("01_Scripts/Feathers/analyst_counts.feather"))


# ──────────────────────────────────────────────────────────────────────────────
# 6️⃣ Render Report -------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# The completion report RMD (11_completion_report.Rmd) is not included in this
# repository. The real report contained sensitive operational data and could not
# be shared publicly. This render call is retained as a placeholder to show how
# the master log fed into a final HTML report delivered to the enforcement team.
rmarkdown::render(
  input       = here("01_Scripts/11_completion_report.Rmd"),
  output_file = "transcription_completion_report.html",
  output_dir  = here("04_Documents"),
  envir       = new.env()  
)


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────