import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static get targets() {
    return ["button"]
  }

  async download(event) {
    event.preventDefault()

    const url = this.exportUrl()
    this.setBusy(true)

    try {
      const response = await fetch(url, {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })

      if (!response.ok) throw new Error(`Export failed with HTTP ${response.status}`)

      const blob = await response.blob()
      this.saveBlob(blob, this.filenameFrom(response) || this.fallbackFilename())
    } catch (error) {
      console.error(error)
      window.location.assign(url.toString())
    } finally {
      this.setBusy(false)
    }
  }

  exportUrl() {
    const url = new URL(this.element.action, window.location.href)
    const formData = new FormData(this.element)

    url.search = ""
    formData.forEach((value, key) => {
      url.searchParams.append(key, value)
    })

    return url
  }

  saveBlob(blob, filename) {
    const downloadUrl = URL.createObjectURL(blob)
    const link = document.createElement("a")

    link.href = downloadUrl
    link.download = filename
    link.hidden = true
    document.body.appendChild(link)
    link.click()
    link.remove()

    window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 1000)
  }

  filenameFrom(response) {
    const header = response.headers.get("Content-Disposition") || ""
    const encodedMatch = header.match(/filename\*=UTF-8''([^;]+)/i)
    if (encodedMatch) return decodeURIComponent(encodedMatch[1])

    const quotedMatch = header.match(/filename="([^"]+)"/i)
    if (quotedMatch) return quotedMatch[1]

    const plainMatch = header.match(/filename=([^;]+)/i)
    return plainMatch ? plainMatch[1].trim() : null
  }

  fallbackFilename() {
    return this.element.dataset.errorExportFilename || "logister-error-export.json"
  }

  setBusy(isBusy) {
    if (!this.hasButtonTarget) return

    if (isBusy) {
      this.buttonTarget.dataset.originalText = this.buttonTarget.textContent
      this.buttonTarget.textContent = "Preparing..."
      this.buttonTarget.disabled = true
    } else {
      this.buttonTarget.textContent = this.buttonTarget.dataset.originalText || "Export JSON"
      this.buttonTarget.disabled = false
    }
  }
}
