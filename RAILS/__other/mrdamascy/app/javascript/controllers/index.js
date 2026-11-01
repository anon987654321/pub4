// Eager-load every mrdamascy controller (§8). Identifiers are kebab-case to
// match Rails-dasherized data attributes (item_sheet_controller.js registers
// as "item-sheet", per the brgen/amber convention).
import { application } from "./application"

import ItemSheetController from "./item_sheet_controller"
import CartBarController from "./cart_bar_controller"
import ZoneCheckController from "./zone_check_controller"
import VippsMockController from "./vipps_mock_controller"
import TrackController from "./track_controller"
import ToastController from "./toast_controller"

application.register("item-sheet", ItemSheetController)
application.register("cart-bar", CartBarController)
application.register("zone-check", ZoneCheckController)
application.register("vipps-mock", VippsMockController)
application.register("track", TrackController)
application.register("toast", ToastController)
