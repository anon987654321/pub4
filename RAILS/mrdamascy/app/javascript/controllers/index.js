// Eager-load every mrdamascy controller (§8). Identifiers are kebab-case to
// match Rails-dasherized data attributes (item_sheet_controller.js registers
// as "item-sheet", per the brgen/amber convention).
// The application module rides the importmap pin ("controllers/application"
// → its digested Propshaft URL); a relative "./application" here would
// bypass the importmap and resolve to an undigested 404 under Propshaft,
// silently killing every Stimulus binding in the app.
import { application } from "controllers/application"

import ItemSheetController from "controllers/item_sheet_controller"
import CartBarController from "controllers/cart_bar_controller"
import ZoneCheckController from "controllers/zone_check_controller"
import VippsMockController from "controllers/vipps_mock_controller"
import TrackController from "controllers/track_controller"
import ToastController from "controllers/toast_controller"
import RetryController from "controllers/retry_controller"
import BoardController from "controllers/board_controller"
import CategorySpyController from "controllers/category_spy_controller"
import PrintController from "controllers/print_controller"

application.register("item-sheet", ItemSheetController)
application.register("cart-bar", CartBarController)
application.register("zone-check", ZoneCheckController)
application.register("vipps-mock", VippsMockController)
application.register("track", TrackController)
application.register("toast", ToastController)
application.register("retry", RetryController)
application.register("board", BoardController)
application.register("category-spy", CategorySpyController)
application.register("print", PrintController)
