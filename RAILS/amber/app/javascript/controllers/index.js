import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { bootPub4Stimulus } from "pub4/stimulus_boot"
import { bootSocialStimulus } from "pub4/stimulus_boot_social"
import { bootAmberStimulus } from "pub4/stimulus_boot_amber"

bootPub4Stimulus(application)
bootSocialStimulus(application)
bootAmberStimulus(application)
eagerLoadControllersFrom("controllers", application)
