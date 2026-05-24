import "@hotwired/turbo-rails"
import "analytics"
import { application } from "controllers/application"
import CountupController from "controllers/countup_controller"
import NavController from "controllers/nav_controller"
import RevealController from "controllers/reveal_controller"
import ScreenshotsSliderController from "controllers/screenshots_slider_controller"

application.register("countup", CountupController)
application.register("nav", NavController)
application.register("reveal", RevealController)
application.register("screenshots-slider", ScreenshotsSliderController)
