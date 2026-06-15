import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { registerStimulusComponents } from "register_stimulus_components"

eagerLoadControllersFrom("controllers", application)
registerStimulusComponents(application)