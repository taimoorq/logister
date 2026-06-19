import { application } from "controllers/application"
import CopyController from "controllers/copy_controller"
import CountupController from "controllers/countup_controller"
import DashboardAttentionController from "controllers/dashboard_attention_controller"
import DashboardExplorerController from "controllers/dashboard_explorer_controller"
import ErrorExportController from "controllers/error_export_controller"
import FrameTabsController from "controllers/frame_tabs_controller"
import HelloController from "controllers/hello_controller"
import InboxController from "controllers/inbox_controller"
import LocalTimeController from "controllers/local_time_controller"
import NavController from "controllers/nav_controller"
import PerformanceBreakdownController from "controllers/performance_breakdown_controller"
import ProductTourController from "controllers/product_tour_controller"
import ProjectInsightsController from "controllers/project_insights_controller"
import ProjectSearchController from "controllers/project_search_controller"
import RevealController from "controllers/reveal_controller"
import ScreenshotsSliderController from "controllers/screenshots_slider_controller"
import TabsController from "controllers/tabs_controller"

application.register("copy", CopyController)
application.register("countup", CountupController)
application.register("dashboard-attention", DashboardAttentionController)
application.register("dashboard-explorer", DashboardExplorerController)
application.register("error-export", ErrorExportController)
application.register("frame-tabs", FrameTabsController)
application.register("hello", HelloController)
application.register("inbox", InboxController)
application.register("local-time", LocalTimeController)
application.register("nav", NavController)
application.register("performance-breakdown", PerformanceBreakdownController)
application.register("product-tour", ProductTourController)
application.register("project-insights", ProjectInsightsController)
application.register("project-search", ProjectSearchController)
application.register("reveal", RevealController)
application.register("screenshots-slider", ScreenshotsSliderController)
application.register("tabs", TabsController)
