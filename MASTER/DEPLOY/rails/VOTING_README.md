# Voting System

Shared voting subsystem used across brgen apps.

Script: `rails/__shared/voting_system.sh`

## Deploy

```zsh
cd ~/pub4/MASTER/DEPLOY/rails
doas zsh voting_system.sh
```

Installs vote models, controllers, and ActionCable channels into the target app.
