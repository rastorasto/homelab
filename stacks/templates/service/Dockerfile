# Service scaffold — copy this whole directory as the skeleton of a new service repo.
#
# Add-a-service protocol (see AGENTS.md):
#   1. create repo on forgejo (e.g. rasto/<svc>) and clone into $APP_REPOS/<svc>
#   2. cp -r ~/docker/stacks/templates/service/* ~/repos/<svc>/   and remove this README
#   3. rename "myservice" everywhere in compose.yml (service name, image, container_name, caddy host)
#   4. add the repo URL to ~/docker/repos.conf, push
# Compose project name = the checkout directory name; ./lab <cmd> <svc> just works.

FROM python:3.12-slim

WORKDIR /app
# COPY your app source and deps here, e.g.:
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt
# COPY . .

EXPOSE 8080

CMD ["python", "-m", "http.server", "8080"]
