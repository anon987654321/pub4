import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { registerStimulusComponents } from "register_stimulus_components"
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"

eagerLoadControllersFrom("controllers", application)
registerStimulusComponents(application)

StimulusReflex.initialize(application, { applicationController: ApplicationController, isolate: true })