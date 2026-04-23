# ====================================================
# Script: 03_run_transcription_gadget_helper.R

# Purpose: Interactive Shiny gadget for configuring
#          WhisperX transcription runs. Provides a
#          user-friendly interface for selecting
#          transcription parameters and analyst folder
#          before execution.

# Author:  Dane Tipene
# Last updated: 2026-03-30
# ====================================================

# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Load Libraries ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

helper_packages <- c("shiny", "miniUI")

for (pkg in helper_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  library(pkg, character.only = TRUE)
}

# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Build Function ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

get_transcription_config <- function() {
  
  ui <- miniPage(
    
    tags$head(
      tags$style(HTML("
        body { font-family: 'Segoe UI', sans-serif; background-color: #f4f6f9; }
        .gadget-title { background-color: #1a3a5c; color: white; padding: 14px 20px; font-size: 15px; font-weight: 600; letter-spacing: 0.3px; }
        .card { background: white; border-radius: 8px; padding: 20px 24px; margin-bottom: 14px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
        .card-title { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.8px; color: #1a3a5c; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 2px solid #e8ecf0; }
        .form-group label { font-size: 13px; font-weight: 600; color: #444; }
        .form-control, .selectize-input { border: 1px solid #dde2e8 !important; border-radius: 5px !important; font-size: 13px !important; color: #333 !important; }
        .confirm-box { background: #eaf2fb; border: 1px solid #b8d4ed; border-radius: 6px; padding: 12px 16px; font-size: 12px; color: #1a3a5c; line-height: 1.7; margin-top: 4px; }
        .confirm-box strong { display: inline-block; min-width: 140px; color: #0d2440; }
        .btn-run { background-color: #1a3a5c; color: white; border: none; border-radius: 5px; padding: 8px 22px; font-size: 13px; font-weight: 600; }
        .btn-run:hover { background-color: #0d2440; color: white; }
        .btn-cancel { background-color: white; color: #666; border: 1px solid #ccc; border-radius: 5px; padding: 8px 18px; font-size: 13px; margin-right: 8px; }
        .gadget-content { padding: 16px 20px; overflow-y: auto; }
      "))
    ),
    
    div(class = "gadget-title", "🎙️  WhisperX Transcription — Run Configuration"),
    
    miniContentPanel(
      div(class = "gadget-content",
          
          # ── Analyst ──
          # Each analyst is pre-assigned a dedicated SharePoint folder by the
          # pipeline owner. The dropdown routes each analyst to their own folder
          # only — no analyst has visibility into another's assigned files.
          # Analysts never see a file list, folder structure, or queue.
          # Selecting their name is their only interaction. The pipeline silently
          # discovers all audio files within their folder (recursively),
          # transcribes each one, and uploads outputs alongside the source file.
          # This design distributes processing load across team hardware while
          # preserving call privacy.
          div(class = "card",
              div(class = "card-title", "Analyst"),
              selectInput("analyst_name", "Select Your Name",
                          choices  = c("Analyst A", "Analyst B", "Analyst C",
                                       "Analyst D", "Analyst E", "Analyst F",
                                       "Analyst G"),
                          selected = NULL,
                          width    = "100%")
          ),
          
          # ── HF Token ──
          div(class = "card",
              div(class = "card-title", "Hugging Face Token"),
              passwordInput("hf_token", "Token", value = "", width = "100%")
          ),
          
          # ── Model Settings ──
          div(class = "card",
              div(class = "card-title", "Model Settings"),
              fluidRow(
                column(6, selectInput("model_size", "Model Size",
                                      choices  = c("tiny", "base", "small", "medium", "large-v2", "large-v3", "large-v3-turbo"),
                                      selected = "large-v3",
                                      width    = "100%")),
                column(6, textInput("language", "Language Code",
                                    value = "en",
                                    width = "100%"))
              ),
              fluidRow(
                column(6, numericInput("min_speakers", "Min Speakers",
                                       value = 2, min = 1, max = 20, width = "100%")),
                column(6, numericInput("max_speakers", "Max Speakers",
                                       value = 6, min = 1, max = 20, width = "100%"))
              ),
              checkboxInput("local_run", "Offline Mode (local_run)", value = TRUE)
          ),
          
          # ── Output Formats ──
          div(class = "card",
              div(class = "card-title", "Output Formats"),
              fluidRow(
                column(3, checkboxInput("save_json", "JSON", value = FALSE)),
                column(3, checkboxInput("save_txt",  "TXT",  value = TRUE)),
                column(3, checkboxInput("save_srt",  "SRT",  value = FALSE)),
                column(3, checkboxInput("save_csv",  "CSV",  value = TRUE))
              )
          ),
          
          # ── Summary ──
          div(class = "card",
              div(class = "card-title", "Summary"),
              uiOutput("summary_box")
          ),
          
          div(style = "text-align: right; margin-top: 4px;",
              actionButton("cancel",  "Cancel",        class = "btn-cancel"),
              actionButton("confirm", "Confirm & Run", class = "btn-run")
          )
      )
    )
  )
  
  server <- function(input, output, session) {
    
    output$summary_box <- renderUI({
      
      if (is.null(input$analyst_name) || input$analyst_name == "") {
        return(div(class = "confirm-box", "⚠️  Please select your name to continue."))
      }
      if (input$hf_token == "" && !input$local_run) {
        return(div(class = "confirm-box", "⚠️  Please enter your Hugging Face token."))
      }
      
      formats <- c(
        if (input$save_json) "JSON",
        if (input$save_txt)  "TXT",
        if (input$save_srt)  "SRT",
        if (input$save_csv)  "CSV"
      )
      
      div(class = "confirm-box", HTML(paste(
        paste0("<strong>Analyst:</strong> ",       input$analyst_name),
        paste0("<strong>Model Size:</strong> ",    input$model_size),
        paste0("<strong>Language:</strong> ",      input$language),
        paste0("<strong>Speakers:</strong> ",      input$min_speakers, " – ", input$max_speakers),
        paste0("<strong>Output Formats:</strong> ", paste(formats, collapse = ", ")),
        paste0("<strong>Offline Mode:</strong> ",  if (input$local_run) "Yes" else "No"),
        sep = "<br>"
      )))
    })
    
    observeEvent(input$confirm, {
      if (is.null(input$analyst_name) || input$analyst_name == "") {
        showNotification("Please select your name.", type = "error")
        return()
      }
      if (input$hf_token == "" && !input$local_run) {
        showNotification("Please enter your Hugging Face token.", type = "error")
        return()
      }
      stopApp(list(
        analyst_name  = input$analyst_name,
        model_size    = input$model_size,
        language      = input$language,
        min_speakers  = input$min_speakers,
        max_speakers  = input$max_speakers,
        save_json     = input$save_json,
        save_txt      = input$save_txt,
        save_srt      = input$save_srt,
        save_csv      = input$save_csv,
        local_run     = input$local_run,
        hf_token      = input$hf_token
      ))
    })
    
    observeEvent(input$cancel, { stopApp(NULL) })
  }
  
  # Launch gadget
  result <- runGadget(ui, server,
                      viewer       = browserViewer(),
                      stopOnCancel = FALSE)
  
  # Release all httpuv handles
  httpuv::stopAllServers()
  
  # Handle cancel
  if (is.null(result)) stop("Script aborted by user.")
  
  # Unpack into global environment
  analyst_name  <<- result$analyst_name
  model_size    <<- result$model_size
  language      <<- result$language
  min_speakers  <<- result$min_speakers
  max_speakers  <<- result$max_speakers
  save_json     <<- result$save_json
  save_txt      <<- result$save_txt
  save_srt      <<- result$save_srt
  save_csv      <<- result$save_csv
  local_run     <<- result$local_run
  hf_token      <<- result$hf_token
}


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────