import { Controller } from "@hotwired/stimulus"

// Chart controller — loads Chart.js only when a chart element is on the page
export default class extends Controller {
  static values = {
    options: {
      type: Object,
      default: {}
    }
  }

  async connect() {
    if (!window.Chart) {
      await import("chart")
    }

    if (!window.Chart) {
      console.error("Chart.js failed to load")
      return
    }

    this.initDarkModeObserver()
    this.initChart()
  }

  disconnect() {
    this.darkModeObserver?.disconnect()
    this.chart?.destroy()
  }

  initChart() {
    this.setColors()
    const ctx = this.element.getContext("2d")
    this.chart = new window.Chart(ctx, this.mergeOptionsWithDefaults())
  }

  setColors() {
    this.setDefaultColorsForChart()
  }

  getThemeColor(name) {
    const color = getComputedStyle(document.documentElement).getPropertyValue(`--${name}`)
    const [ hue, saturation, lightness ] = color.split(" ")
    return `hsl(${hue}, ${saturation}, ${lightness})`
  }

  defaultThemeColor() {
    return {
      backgroundColor: this.getThemeColor("background"),
      hoverBackgroundColor: this.getThemeColor("accent"),
      borderColor: this.getThemeColor("primary"),
      borderWidth: 1
    }
  }

  setDefaultColorsForChart() {
    const Chart = window.Chart

    Chart.defaults.color = this.getThemeColor("muted-foreground")
    Chart.defaults.borderColor = this.getThemeColor("border")
    Chart.defaults.backgroundColor = this.getThemeColor("background")

    Chart.defaults.plugins.tooltip.backgroundColor = this.getThemeColor("background")
    Chart.defaults.plugins.tooltip.borderColor = this.getThemeColor("border")
    Chart.defaults.plugins.tooltip.titleColor = this.getThemeColor("foreground")
    Chart.defaults.plugins.tooltip.bodyColor = this.getThemeColor("muted-foreground")
    Chart.defaults.plugins.tooltip.borderWidth = 1

    Chart.defaults.plugins.legend.labels.boxWidth = 12
    Chart.defaults.plugins.legend.labels.boxHeight = 12
    Chart.defaults.plugins.legend.labels.borderWidth = 0
    Chart.defaults.plugins.legend.labels.useBorderRadius = true
    Chart.defaults.plugins.legend.labels.borderRadius = this.getThemeColor("radius")
  }

  refreshChart() {
    this.chart?.destroy()
    this.initChart()
  }

  initDarkModeObserver() {
    this.darkModeObserver = new MutationObserver(() => {
      this.refreshChart()
    })
    this.darkModeObserver.observe(document.documentElement, { attributeFilter: [ "class" ] })
  }

  mergeOptionsWithDefaults() {
    return {
      ...this.optionsValue,
      data: {
        ...this.optionsValue.data,
        datasets: this.optionsValue.data.datasets.map((dataset) => {
          return {
            ...this.defaultThemeColor(),
            ...dataset
          }
        })
      }
    }
  }
}
