// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "./analytics"

async function writeClipboardText(text) {
  if (!text) return false

  const execResult = copyViaExecCommand(text)
  debugClipboard("execCommand result", { copied: execResult })
  if (execResult) return true

  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text)
      debugClipboard("navigator.clipboard result", { copied: true })
      return true
    } catch (error) {
      debugClipboard("navigator.clipboard error", {
        name: error && error.name,
        message: error && error.message
      })
      return false
    }
  }

  debugClipboard("clipboard unavailable", {
    hasNavigatorClipboard: !!navigator.clipboard,
    isSecureContext: !!window.isSecureContext
  })
  return false
}

function copyViaExecCommand(text) {
  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "")
  textarea.style.position = "absolute"
  textarea.style.left = "-9999px"
  document.body.appendChild(textarea)
  textarea.focus()
  textarea.select()
  textarea.setSelectionRange(0, textarea.value.length)

  let copied = false
  try {
    copied = document.execCommand("copy")
  } catch (_error) {
    copied = false
  }

  document.body.removeChild(textarea)
  return copied
}

function debugClipboard(message, details = {}) {
  if (!window.LOGISTER_DEBUG_CLIPBOARD) return
  console.log("[clipboard_fallback]", message, details)
}

async function handleCopyButton(button) {
  if (!(button instanceof HTMLElement)) return

  const block = button.closest(".copy-block")
  if (!(block instanceof HTMLElement)) return

  const source = block.querySelector("[data-copy-target='source']")
  const sourceText = source && typeof source.textContent === "string" ? source.textContent.trim() : ""
  const text = block.dataset.copyTextValue || sourceText
  debugClipboard("fallback copy requested", {
    textLength: text ? text.length : 0
  })
  const copied = await writeClipboardText(text)

  const label = block.querySelector("[data-copy-target='buttonLabel']")
  if (!(label instanceof HTMLElement)) return

  const original = label.textContent
  if (copied) {
    label.textContent = "Copied"
    block.classList.add("is-copied")
  } else {
    label.textContent = "Failed"
    block.classList.add("is-copy-failed")
  }

  window.setTimeout(() => {
    label.textContent = original
    block.classList.remove("is-copied")
    block.classList.remove("is-copy-failed")
  }, 1200)
}

document.addEventListener("click", async (event) => {
  const button = event.target && event.target.closest ? event.target.closest(".copy-block-btn") : null
  if (!(button instanceof HTMLElement)) return
  await handleCopyButton(button)
}, true)

window.logisterCopyButton = function logisterCopyButton(button) {
  if (!(button instanceof HTMLElement)) return
  handleCopyButton(button)
}
