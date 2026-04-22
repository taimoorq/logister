import { application } from "controllers/application"
import CopyController from "controllers/copy_controller"
import CountupController from "controllers/countup_controller"
import FrameTabsController from "controllers/frame_tabs_controller"
import HelloController from "controllers/hello_controller"
import InboxController from "controllers/inbox_controller"
import LocalTimeController from "controllers/local_time_controller"
import NavController from "controllers/nav_controller"
import ProjectSearchController from "controllers/project_search_controller"
import RevealController from "controllers/reveal_controller"
import ScreenshotsSliderController from "controllers/screenshots_slider_controller"
import TabsController from "controllers/tabs_controller"

application.register("copy", CopyController)
application.register("countup", CountupController)
application.register("frame-tabs", FrameTabsController)
application.register("hello", HelloController)
application.register("inbox", InboxController)
application.register("local-time", LocalTimeController)
application.register("nav", NavController)
application.register("project-search", ProjectSearchController)
application.register("reveal", RevealController)
application.register("screenshots-slider", ScreenshotsSliderController)
application.register("tabs", TabsController)
