# ====================================================
# Script: 10_stitch_transcriptions.R

# Purpose: Recursively searches a SharePoint folder
#          containing customer subfolders, finds all
#          CSV transcription files beginning with
#          "Transcribed-", stitches them into a single
#          dataframe per customer, and uploads a
#          formatted Word document to each customer's
#          root folder on SharePoint.

# Usage:   Configure Section 1, then run the script.

# Author:  Dane Tipene
# Last updated: 2026-04-30
# ====================================================


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Configuration -------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Replace these values with your organisation's SharePoint details
sharepoint_site_url  <- "https://your-organisation.sharepoint.com/teams/your-team"
drive_name           <- "Documents"
sharepoint_base_path <- "path/to/your/transcription/folder"


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Load Libraries ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

stitch_packages <- c("dplyr", "here", "Microsoft365R", "officer", "purrr", "readr", "stringr")

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


# ──────────────────────────────────────────────────────────────────────────────
# 4️⃣ Helper Functions ----------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Recursively find all Transcribed- CSV files within a folder path
get_transcription_files <- function(drive, folder_path) {
  
  items <- tryCatch(
    drive$list_items(folder_path),
    error = function(e) {
      cat("  ⚠️  Could not access:", folder_path, "\n")
      return(list())
    }
  )
  
  if (length(items) == 0) return(tibble())
  
  items_df <- bind_rows(items)
  
  if (nrow(items_df) == 0) return(tibble())
  
  # Filter for Transcribed- CSV files
  csvs <- items_df %>%
    filter(
      !isdir,
      str_detect(name, "^Transcribed-.*\\.csv$")
    ) %>%
    mutate(folder_path = folder_path)
  
  # Recurse into subfolders
  folders <- items_df %>% filter(isdir)
  
  if (nrow(folders) > 0) {
    subfolder_csvs <- bind_rows(lapply(folders$name, function(f) {
      get_transcription_files(drive, paste0(folder_path, "/", f))
    }))
    csvs <- bind_rows(csvs, subfolder_csvs)
  }
  
  return(csvs)
}


# Download, read, and stitch all CSVs for a single customer
build_customer_df <- function(drive, csv_files_df, temp_dir) {
  
  results <- lapply(seq_len(nrow(csv_files_df)), function(i) {
    
    file_name <- csv_files_df$name[i]
    sp_path   <- paste0(csv_files_df$folder_path[i], "/", file_name)
    local_path <- file.path(temp_dir, file_name)
    
    tryCatch({
      drive$download_file(sp_path, dest = local_path, overwrite = TRUE)
      
      df <- read_csv(local_path, show_col_types = FALSE)
      
      # Skip empty transcriptions (unanswered calls)
      if (nrow(df) == 0) {
        cat("    ⚠️  Empty transcription skipped:", file_name, "\n")
        return(NULL)
      }
      
      df %>% mutate(source_file = file_name)
      
    }, error = function(e) {
      cat("    ⚠️  Failed to read:", file_name, "-", conditionMessage(e), "\n")
      return(NULL)
    })
  })
  
  # Drop NULLs and stitch
  results <- compact(results)
  
  if (length(results) == 0) return(NULL)
  
  bind_rows(results) %>%
    select(Speaker, Start, End, Text, source_file) %>%
    arrange(source_file)
}


# Build and write a formatted Word document for a single customer
build_customer_docx <- function(customer_name, customer_df, output_path) {
  
  fp_normal  <- fp_text(font.family = "Aptos Narrow", font.size = 11)
  fp_title   <- fp_text(font.family = "Aptos Narrow", font.size = 16, bold = TRUE)
  fp_heading <- fp_text(font.family = "Aptos Narrow", font.size = 13, bold = TRUE)
  fp_date    <- fp_text(font.family = "Aptos Narrow", font.size = 11, italic = TRUE)
  
  doc <- read_docx()
  
  # ── Title ──
  doc <- doc %>%
    body_add_fpar(fpar(ftext(customer_name, fp_title))) %>%
    body_add_fpar(fpar(ftext(paste("Transcriptions exported:", format(Sys.Date(), "%d %B %Y")), fp_date))) %>%
    body_add_par("", style = "Normal")
  
  # ── Loop through each source file alphabetically ──
  source_files <- sort(unique(customer_df$source_file))
  
  for (src in source_files) {
    
    call_df <- customer_df %>% filter(source_file == src)
    
    # Source file heading
    doc <- doc %>%
      body_add_fpar(fpar(ftext(src, fp_heading))) %>%
      body_add_par("", style = "Normal")
    
    # Each transcript row as a formatted line
    for (i in seq_len(nrow(call_df))) {
      row  <- call_df[i, ]
      line <- paste0(row$Speaker, "  |  ", row$Start, "  |  ", row$End, "  |  ", row$Text)
      doc  <- doc %>% body_add_fpar(fpar(ftext(line, fp_normal)))
    }
    
    doc <- doc %>% body_add_par("", style = "Normal")
  }
  
  print(doc, target = output_path)
}


# ──────────────────────────────────────────────────────────────────────────────
# 5️⃣ Get All Customer Folders -------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("=== Listing customer folders ===\n\n")

top_level    <- drive$list_items(sharepoint_base_path)
top_level_df <- bind_rows(top_level)

customer_folders <- top_level_df %>%
  filter(isdir) %>%
  pull(name)

cat("Found", length(customer_folders), "customer folders\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 6️⃣ Process Each Customer ----------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

temp_dir <- tempdir() |> normalizePath(winslash = "/", mustWork = FALSE)

results_log <- tibble(
  customer       = character(),
  files_found    = integer(),
  files_stitched = integer(),
  status         = character()
)

for (customer in customer_folders) {
  
  cat("\n============================================================\n")
  cat("Processing:", customer, "\n")
  cat("============================================================\n")
  
  customer_sp_path <- paste0(sharepoint_base_path, "/", customer)
  
  # ── Find all Transcribed- CSVs ──
  cat("  🔍 Searching for transcription files...\n")
  csv_files_df <- get_transcription_files(drive, customer_sp_path)
  
  if (nrow(csv_files_df) == 0) {
    cat("  ⚠️  No transcription files found — skipping\n")
    results_log <- bind_rows(results_log, tibble(
      customer       = customer,
      files_found    = 0L,
      files_stitched = 0L,
      status         = "No files found"
    ))
    next
  }
  
  cat("  📄 Found", nrow(csv_files_df), "transcription file(s)\n")
  
  # ── Download, read, and stitch ──
  cat("  📥 Downloading and stitching...\n")
  customer_df <- build_customer_df(drive, csv_files_df, temp_dir)
  
  if (is.null(customer_df)) {
    cat("  ⚠️  All files empty — skipping\n")
    results_log <- bind_rows(results_log, tibble(
      customer       = customer,
      files_found    = nrow(csv_files_df),
      files_stitched = 0L,
      status         = "All files empty"
    ))
    next
  }
  
  files_stitched <- n_distinct(customer_df$source_file)
  cat("  ✅ Stitched", files_stitched, "file(s) —", nrow(customer_df), "rows total\n")
  
  # ── Build Word document ──
  cat("  📝 Building Word document...\n")
  docx_filename  <- paste0(customer, "_transcriptions.docx")
  local_docx_path <- file.path(temp_dir, docx_filename)
  
  tryCatch({
    build_customer_docx(customer, customer_df, local_docx_path)
    cat("  ✅ Document created:", docx_filename, "\n")
  }, error = function(e) {
    cat("  ❌ Failed to build document:", conditionMessage(e), "\n")
    results_log <<- bind_rows(results_log, tibble(
      customer       = customer,
      files_found    = nrow(csv_files_df),
      files_stitched = files_stitched,
      status         = paste("docx error:", conditionMessage(e))
    ))
    return()
  })
  
  # ── Upload to SharePoint customer root ──
  cat("  📤 Uploading to SharePoint...\n")
  sp_dest <- paste0(customer_sp_path, "/", docx_filename)
  
  tryCatch({
    drive$upload_file(local_docx_path, dest = sp_dest)
    cat("  ✅ Uploaded:", docx_filename, "\n")
    
    results_log <- bind_rows(results_log, tibble(
      customer       = customer,
      files_found    = nrow(csv_files_df),
      files_stitched = files_stitched,
      status         = "Success"
    ))
  }, error = function(e) {
    cat("  ❌ Upload failed:", conditionMessage(e), "\n")
    results_log <- bind_rows(results_log, tibble(
      customer       = customer,
      files_found    = nrow(csv_files_df),
      files_stitched = files_stitched,
      status         = paste("Upload error:", conditionMessage(e))
    ))
  })
  
  # ── Clean up temp files ──
  unlink(list.files(temp_dir, full.names = TRUE))
}


# ──────────────────────────────────────────────────────────────────────────────
# 7️⃣ Summary Report ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("\n============================================================\n")
cat("✅ Processing complete!\n")
cat("============================================================\n\n")

cat("Summary:\n")
cat("  Total customers processed:", nrow(results_log), "\n")
cat("  Successful:               ", sum(results_log$status == "Success"), "\n")
cat("  Skipped (no files):       ", sum(results_log$status == "No files found"), "\n")
cat("  Skipped (all empty):      ", sum(results_log$status == "All files empty"), "\n")
cat("  Errors:                   ", sum(!results_log$status %in% c("Success", "No files found", "All files empty")), "\n\n")

# Print any errors for review
errors <- results_log %>% filter(!status %in% c("Success", "No files found", "All files empty"))
if (nrow(errors) > 0) {
  cat("⚠️  Customers with errors:\n")
  print(errors)
}


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────