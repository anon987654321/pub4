import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"

eagerLoadControllersFrom("controllers", application)

StimulusReflex.initialize(application, { applicationController: ApplicationController, isolate: true })
