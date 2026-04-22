# pipeline = Master::Pipeline.new(
#   stages: [
#     Master::Stages::Intake,
#     Master::Stages::Infer,
#     Master::Stages::Route,
#     Master::Stages::Guard,   # 📛 Enforces guardrails before execution
#     Master::Stages::Execute,
#     Master::Stages::Council,
#     Master::Stages::Lint,
#     Master::Stages::Memo,
#     Master::Stages::Render,
#   ]
# )
# 