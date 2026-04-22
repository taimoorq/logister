import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static get targets() {
    return ["source", "buttonLabel"]
  }

  static get values() {
    return { text: String }
  }

  connect() {
    this.debug("connected", { id: this.element.id || null })
  }

  disconnect() {
    clearTimeout(this.resetTimer)
  }

  async copy(event) {
    event.preventDefault()

    let text = null
    if (this.hasTextValue) {
      text = this.textValue
    } else if (this.hasSourceTarget && this.sourceTarget && typeof this.sourceTarget.textContent === "string") {
      text = this.sourceTarget.textContent.trim()
    }

    if (!text) {
      this.debug("copy aborted: empty text")
      this.flashFailed()
      return
    }

    this.debug("copy requested", { textLength: text.length })

    const copied = await this.writeText(text)
    this.debug("copy result", { copied })
    if (copied) {
      this.flashCopied()
    } else {
      this.flashFailed()
    }
  }

  async writeText(text) {
    const execResult = this.copyViaExecCommand(text)
    this.debug("execCommand result", { copied: execResult })
    if (execResult) return true

    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text)
        this.debug("navigator.clipboard result", { copied: true })
        return true
      } catch (error) {
        this.debug("navigator.clipboard error", {
          name: error && error.name,
          message: error && error.message
        })
        return false
      }
    }

    this.debug("clipboard unavailable", {
      hasNavigatorClipboard: !!navigator.clipboard,
      isSecureContext: !!window.isSecureContext
    })
    return false
  }

  copyViaExecCommand(text) {
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

  flashCopied() {
    if (!this.hasButtonLabelTarget) return

    const original = this.buttonLabelTarget.textContent
    this.buttonLabelTarget.textContent = "Copied"
    this.element.classList.add("is-copied")

    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => {
      this.buttonLabelTarget.textContent = original
      this.element.classList.remove("is-copied")
    }, 1200)
  }

  flashFailed() {
    if (!this.hasButtonLabelTarget) return

    const original = this.buttonLabelTarget.textContent
    this.buttonLabelTarget.textContent = "Failed"
    this.element.classList.add("is-copy-failed")

    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => {
      this.buttonLabelTarget.textContent = original
      this.element.classList.remove("is-copy-failed")
    }, 1600)
  }

  debug(message, details = {}) {
    if (!window.LOGISTER_DEBUG_CLIPBOARD) return
    console.log("[copy_controller]", message, details)
  }
}
