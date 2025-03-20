# Pasos para instalar el entorno completo en Windows 11

✅ Stack Tecnológico:
| Área              | Tecnología Elegida                    |
|-------------------|---------------------------------------|
| SO Desarrollo     | Windows 11                            |
| SO Freeswitch     | Debian 12 (virtualizado con Hyper-V)  |
| Base de Datos     | PostgreSQL (instalado en Debian 12)   |
| Virtualización    | Hyper-V                               |
| Front-End	        | React.js                              |
| Back-End          | FastAPI (Python)                      |
| Seguridad y Login | JWT + Two-Factor Authentication (2FA) |
| Control de Código | Git / GitHub                          |
| API Testing       | Postman                               |

📁 Estructura recomendada del proyecto:
```console
Ring2All/
│
├── backend/
│   ├── app/
│   │   ├── api/
│   │   │   ├── v1/           # Versionado API REST
│   │   │   │   ├── endpoints # Endpoints específicos
│   │   │   │   └── routers.py
│   │   ├── core/
│   │   │   ├── config.py     # Configuración principal (Base de datos, JWT)
│   │   │   └── security.py   # Manejo de JWT y 2FA
│   │   ├── models/           # Modelos SQLAlchemy para PostgreSQL
│   │   ├── schemas/          # Validación de datos (Pydantic)
│   │   ├── services/         # Servicios externos o lógicas específicas
│   │   ├── utils/            # Herramientas auxiliares, como manejo de logs
│   │   └── main.py           # Archivo principal (FastAPI App)
│   │
│   ├── tests/                # Test del backend (opcional con pytest)
│   ├── requirements.txt      # Dependencias Python
│   └── Dockerfile            # Opcional (para futuros despliegues)
│
├── frontend/
│   ├── public/
│   ├── src/
│   │   ├── components/       # Componentes reutilizables (botones, menús, etc.)
│   │   ├── pages/            # Vistas específicas (login, dashboard, etc.)
│   │   ├── services/         # Lógica de API REST
│   │   ├── context/          # Manejo global de estado
│   │   ├── utils/            # Funciones auxiliares
│   │   └── App.jsx           # App principal
│   │
│   ├── package.json
│   └── tailwind.config.js (opcional, recomendado Tailwind CSS)
│
├── scripts_migracion/        # Tus scripts Python existentes para migración
└── docs/                     # Documentación técnica (opcional, recomendado)
```

🚀 Paso 1: Preparar tu equipo con Windows 11 <br>
🔹 Instalar Git
- Descarga Git desde [aquí](https://git-scm.com/downloads/win).
- Ejecuta el instalador y sigue los pasos predeterminados.
- Verifica la instalación:
```console
git --version
```
🚀 Paso 2: Instalar Python y crear un Entorno Virtual <br>
🔹 Instalar Python (Última versión 3.12.x)
- Descarga Python desde [python.org](https://www.python.org/downloads/windows/).
- Marca la opción "Add Python 3.12.x to PATH" al instalar.
- Completa la instalación con las opciones por defecto.
- Verifica la instalación:
```console
python --version
```
🚀 Paso 3: Instalar Node.js para React.js
- Descarga el LTS desde [nodejs.org](https://nodejs.org/en/download).
- Ejecuta el instalador con opciones predeterminadas.
Verifica:
```console
node -v
npm -v
```
🚀 Paso 4: Descargar e instalar Visual Studio Code
Si aún no lo tienes:
- Visita la página oficial: 👉 https://code.visualstudio.com/download
- Descarga el instalador para Windows 11 (64-bit).
- Ejecuta el instalador con las opciones predeterminadas (marca la opción "Add to PATH" para facilitar el uso desde terminal).

🚀 Paso 5: Instalar extensiones recomendadas en VSCode
Abre Visual Studio Code, ve a la barra lateral izquierda y selecciona el icono Extensions (Ctrl + Shift + X). Luego instala las siguientes extensiones recomendadas escribiendo su nombre en la barra de búsqueda:
- Python (Microsoft)
    - Soporte completo para desarrollo Python.
- Pylance (Microsoft)
    - Mejora autocompletado, sugerencias inteligentes, detección de errores.
- ESLint (Microsoft)
    - Para verificar tu código JavaScript y React.
- Prettier - Code formatter (esbenp)
    - Para formatear automáticamente JavaScript/HTML/CSS.
- GitHub Copilot (opcional, muy recomendado)
    - Inteligencia artificial que ayuda a escribir código más rápido.
- Docker (Microsoft) (opcional)
    - Facilita usar contenedores si en futuro deseas implementar Docker.
- PostgreSQL (opcional)
    - Para gestionar bases de datos PostgreSQL desde VSCode.

🚀 Paso 6: Crear tu entorno virtual desde VSCode
- Abre VSCode.
- Abre una terminal integrada (View → Terminal).
- Ejecuta en la terminal (PowerShell recomendado):
```console
python -m venv env
.\env\Scripts\Activate.ps1
```
Si ves (env) al inicio de la línea en tu terminal, el entorno virtual está activo.

🚀 Paso 7: Instalar dependencias del proyecto (FastAPI y otras)
Con el entorno virtual activo:
```console
pip install fastapi "uvicorn[standard]" sqlalchemy psycopg2-binary pydantic python-jose passlib[bcrypt] pyotp
```

🚀 Paso 8: Instalar Node.js (para React.js)
- Descarga desde la web oficial la versión LTS:
    👉 https://nodejs.org/es/download
- Verifica instalación desde terminal VSCode:
```console
node --version
npm --version
```

🚀 Paso 9: Crear tu proyecto React.js en VSCode
Desde terminal integrada en VSCode, ejecuta (Select: Vanilla y JavaScript):
```console
npm create vite@latest frontend -- --template react
cd frontend
npm install
npm install axios react-router-dom shadcn-ui tailwindcss postcss autoprefixer
npm run dev
```
Al ejecutar verás tu aplicación React funcionando localmente: 👉 http://localhost:5173

🚀 Paso 10: Conectar GitHub a tu proyecto desde VSCode
1.- Inicializa Git: Desde tu terminal integrada en VSCode, ejecuta:
```console
git init
git add .
git commit -m "Proyecto Ring2All inicializado"
```

2.- Conecta con GitHub:
- Ve a GitHub, crea un repositorio vacío.
- Luego en la terminal ejecuta:
```console
git remote add origin https://github.com/TuUsuario/Ring2All.git
git branch -M main
git push -u origin main
```

🚀 Paso 11: Configurar Postman
- Descarga e instala Postman desde: 👉 https://www.postman.com/downloads/
- Abre Postman y crea un workspace nuevo llamado Ring2All.
- Crea y prueba peticiones REST contra http://localhost:8000.

✅ Checklist Final (Herramientas instaladas y configuradas):
- Visual Studio Code ✔️
- Extensiones esenciales (Python, ESLint, Prettier, Docker opcional, GitHub Copilot opcional).
- Python con entorno virtual (FastAPI funcionando).
- Node.js (React funcionando).
- Git + GitHub configurado.
- PostgreSQL operativo.
- Postman instalado y listo para probar API REST.

🚩 Consejos adicionales para tu día a día con VSCode:
- Usa la terminal integrada (Ctrl + ñ) siempre.
- Para activar el entorno virtual Python rápidamente, abre terminal en tu carpeta raíz del proyecto (Ring2All) y ejecuta siempre:
```console
.\env\Scripts\Activate.ps1
```
- Guarda siempre tu entorno virtual activado cuando trabajes en el backend Python.
