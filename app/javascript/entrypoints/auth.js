import "@hotwired/turbo-rails"
import "analytics"
import { application } from "controllers/application"
import NavController from "controllers/nav_controller"

application.register("nav", NavController)
