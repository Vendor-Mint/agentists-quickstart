# K8s Cloud Workspace

Este proyecto proporciona un entorno de desarrollo profesional y pre-configurado basado en **DevContainers**, diseñado para trabajar de forma nativa en la nube y Kubernetes. El objetivo es ofrecer una experiencia de desarrollo consistente, potente y automatizada, integrando herramientas de IA, cloud y automatización de navegadores.

## Herramientas Incluidas

- **Cloud & Infra**: Google Cloud CLI (`gcloud`), Kubernetes tools (`kubectl`, `helm`), Cloudflare (`cloudflared`).
- **Lenguajes**: Node.js (LTS), Python (Latest), .NET (Latest).
- **IA & Productividad**: Claude Code CLI con soporte para servidores MCP (Model Context Protocol).
- **Utilidades**: Docker-in-Docker, Tmux, Git, Playwright (con Chromium).

## Servidores MCP Configurados en Claude Code

Al iniciar el contenedor, Claude Code se configura automáticamente con los siguientes servidores MCP:
- **Playwright**: Automatización y navegación web.
- **GitHub**: Integración con repositorios y gestión de issues/PRs.
- **Context7**: Documentación técnica actualizada de librerías y frameworks.
- **Filesystem**: Acceso seguro al sistema de archivos del workspace.
- **Atlassian**: Integración con Jira y Confluence mediante OAuth.

---

## Requisitos Previos

Antes de iniciar, asegúrate de tener las siguientes variables de entorno configuradas en tu máquina local:

- `ANTHROPIC_API_KEY`: Tu llave de API de Anthropic para usar Claude Code.
- `GITHUB_PERSONAL_ACCESS_TOKEN`: Token clásico con permisos de `repo` para el MCP de GitHub.

---

## Cómo Construir la Imagen con Docker

Si deseas construir la imagen manualmente para inspeccionarla o desplegarla en un registro:

1. Asegúrate de estar en la raíz del proyecto.
2. Ejecuta el comando de construcción:

```bash
docker build -t k8s-cloud-workspace:latest -f .devcontainer/Dockerfile .
```
*(Nota: Si no usas un Dockerfile personalizado, VS Code/DevPod construirán la imagen automáticamente usando la configuración de `devcontainer.json`).*

---

## Cómo usar en VS Code

1. Instala la extensión **Dev Containers** de Microsoft.
2. Abre la carpeta del proyecto en VS Code.
3. Presiona `F1` y selecciona: **Dev Containers: Reopen in Container**.
4. VS Code construirá la imagen e iniciará el entorno. Al finalizar, el script `on-create.sh` configurará automáticamente los servidores MCP.

---

## Cómo usar en DevPod

DevPod permite llevar este entorno a cualquier infraestructura (Kubernetes, AWS, GCP, etc.):

1. Instala [DevPod](https://devpod.sh/).
2. Añade el repositorio del proyecto:
   ```bash
   devpod add [URL_DE_TU_REPO]
   ```
3. Inicia el workspace seleccionando tu proveedor (ej. Kubernetes):
   ```bash
   devpod up .
   ```
4. DevPod detectará automáticamente el archivo `.devcontainer/devcontainer.json` y aprovisionará el entorno en tu cluster.

---

## Notas Técnicas
- **Persistencia en /tmp**: El workspace utiliza un volumen dedicado para `/tmp` para evitar problemas de espacio en memoria (tmpfs) y asegurar la persistencia de caches grandes durante las sesiones.
- **Autenticación Jira**: El MCP de Atlassian utiliza OAuth. La primera vez que interactúes con herramientas de Jira/Confluence desde Claude, se te pedirá autenticarte mediante una ventana del navegador.
