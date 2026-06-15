import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import StimulusReflex from "stimulus_reflex"
import ApplicationController from "controllers/application_controller"

eagerLoadControllersFrom("controllers", application)

StimulusReflex.initialize(application, { applicationController: ApplicationController, isolate: true })

// Futurism (for Pagy + infinite scroll per ruby_style.yml stimulus_reflex_stack)
import Futurism from "@stimulus_reflex/futurism"
application.register("futurism", Futurism)
