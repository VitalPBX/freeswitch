# Pasos para instalar el entorno completo en Windows 11

## Paso 1: Instalar herramientas básicas
### 1.- Python 3.13:
Descarga el instalador desde python.org.
Ejecuta el instalador:
Marca "Add Python 3.11 to PATH".
Selecciona "Install Now".
Verifica la instalación:
```console
C:\Windows\System32>python --version
Python 3.13.2
```

### 2.- Node.js 22.14 (LTS):
Descarga el instalador desde nodejs.org.
Ejecuta el instalador con opciones predeterminadas (incluye npm).
Verifica:
```console
C:\Windows\System32>node -v
v22.14.0
console
```console
C:\Windows\System32>npm -v
10.9.2
```

### 3.- Git:
Descarga desde git-scm.com.
Ejecuta el instalador:
Usa las opciones predeterminadas (Git Bash incluido).
Configura tu identidad:
```console
git config --global user.name "TuNombre"
git config --global user.email "tuemail@example.com"
```
Verifica:
```console
C:\Windows\System32>git --version
git version 2.49.0.windows.1
```

### 4.- Visual Studio Code (VSCode):
Descarga desde code.visualstudio.com.
Ejecuta el instalador.
Abre VSCode y agrega extensiones:
Abre el panel de extensiones (Ctrl+Shift+X) y busca:
Python (Microsoft).
ESLint (Dirk Baeumer).
Prettier - Code formatter (Prettier).
GitLens (Eric Amodio).
Instala cada una.

### 5.- Postman:
Descarga desde postman.com.
Ejecuta el instalador.
Inicia sesión con tu cuenta existente y crea un nuevo workspace (por ejemplo, "FreeSWITCH Admin").

## Paso 2: Configurar el entorno de desarrollo
### 1.- Crear la carpeta del proyecto:
Abre una terminal (CMD o PowerShell):
```console
mkdir freeswitch_admin
cd freeswitch_admin
mkdir backend frontend
```
### 2.- Clonar tu repositorio de GitHub (opcional):
Si ya tienes código en GitHub:
```console
git clone https://github.com/<tu_usuario>/<tu_repositorio>.git
```
Si no, trabajarás desde cero y subirás después.

## Paso 3: Configurar el Back-end (FastAPI)
### 1.- Crear un entorno virtual:
```console
cd backend
python -m venv venv
venv\Scripts\activate
```
Verás (venv) en la terminal.
  
### 2.- Instalar dependencias:
```console
pip install fastapi uvicorn python-jose[cryptography] passlib[bcrypt] pyotp sqlalchemy psycopg2-binary
```

### 3.- Crear la estructura básica:
Crea los siguientes archivos en backend/:
```console
type nul > main.py
type nul > database.py
mkdir routes
cd routes
type nul > auth.py
cd ..
```

### 4.- Configurar la conexión a PostgreSQL:
Edita database.py:

#### backend/database.py
```console
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
```

#### Reemplaza con la IP de tu VM Debian 12, usuario y contraseña
```console
DATABASE_URL = "postgresql://<usuario>:<contraseña>@<ip_vm>:5432/ring2all"
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

### 5.- Configurar el archivo principal:
Edita main.py:

#### backend/main.py
```console
from fastapi import FastAPI, Depends
from routes.auth import router as auth_router
from database import get_db

app = FastAPI()

app.include_router(auth_router, prefix="/auth")

@app.get("/")
def read_root():
    return {"message": "Welcome to FreeSWITCH Admin API"}

@app.get("/dialplan")
def get_dialplan(db=Depends(get_db)):
    result = db.execute("SELECT context_name, expression FROM public.dialplan").fetchall()
    return [{"context_name": row[0], "expression": row[1]} for row in result]
```

### 6.- Configurar el endpoint de autenticación:
Edita routes/auth.py:

#### backend/routes/auth.py
```console
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
import pyotp
from database import get_db

router = APIRouter()

class LoginRequest(BaseModel):
    username: str
    password: str

class TwoFARequest(BaseModel):
    username: str
    otp: str

# Simulación de DB (reemplaza con tu tabla de usuarios en PostgreSQL)
users_db = {"admin": {"password": "admin123", "secret": pyotp.random_base32()}}

@router.post("/login")
def login(request: LoginRequest):
    user = users_db.get(request.username)
    if not user or request.password != user["password"]:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return {"message": "Enter OTP", "username": request.username}

@router.post("/2fa")
def verify_2fa(request: TwoFARequest):
    user = users_db.get(request.username)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    totp = pyotp.TOTP(user["secret"])
    if totp.verify(request.otp):
        return {"token": "jwt_token_here"}  # Implementa JWT en producción
    raise HTTPException(status_code=401, detail="Invalid OTP")
```

### 7.- Ejecutar el Back-end (en el entorno virtual: (venv) D:\freeswitch_admin\backend>):
Para ingresar al entorno virtual:
```console
D:\freeswitch_admin\backend\venv\Scripts\Activate.ps1
```
```console
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Prueba en tu navegador: http://localhost:8000/.
Usa Postman:
- POST http://localhost:8000/auth/login con {"username": "admin", "password": "admin123"}.
- Copia el OTP generado por pyotp.TOTP(users_db["admin"]["secret"]).now() y prueba POST http://localhost:8000/auth/2fa.

## Paso 4: Configurar el Front-end (React) (en el entorno virtual: (venv) D:\freeswitch_admin\backend>):
Abre una nueva Terminal:
```console
D:\freeswitch_admin\backend\venv\Scripts\Activate.ps1
```
### 1.- Crear el proyecto React:
```console
cd ..\frontend
npx create-react-app .
npm install @mui/material @emotion/react @emotion/styled react-router-dom axios react-otp-input
```

### 2.- Configurar la estructura
```console
mkdir src\components
cd src\components
type nul > Sidebar.js
type nul > Login.js
cd ..\..
```

### 3.- Configurar el archivo principal
Edita src/App.js:
```console
// src/App.js
import React from 'react';
import { BrowserRouter as Router, Route, Routes } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import Login from './components/Login';

function App() {
  return (
    <Router>
      <div style={{ display: 'flex' }}>
        <Sidebar />
        <div style={{ flex: 1, padding: '20px' }}>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/" element={<h1>Welcome</h1>} />
          </Routes>
        </div>
      </div>
    </Router>
  );
}

export default App;
```

### 4.- Configurar el menú lateral:
Edita src/components/Sidebar.js:
```console
// src/components/Sidebar.js
import React from 'react';
import { Drawer, List, ListItem, ListItemText } from '@mui/material';
import { Link } from 'react-router-dom';

const Sidebar = () => {
  return (
    <Drawer variant="permanent" anchor="left">
      <List>
        <ListItem button component={Link} to="/login">
          <ListItemText primary="Login" />
        </ListItem>
      </List>
    </Drawer>
  );
};

export default Sidebar;
```

### 5.- Configurar el login con 2FA:
Edita src/components/Login.js:
```console
// src/components/Login.js
import React, { useState } from 'react';
import { TextField, Button } from '@mui/material';
import OtpInput from 'react-otp-input';
import axios from 'axios';

const Login = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [step, setStep] = useState('login');

  const handleLogin = async () => {
    try {
      const response = await axios.post('http://localhost:8000/auth/login', { username, password });
      if (response.data.message === "Enter OTP") {
        setStep('otp');
      }
    } catch (error) {
      alert('Login failed');
    }
  };

  const handleOtp = async () => {
    try {
      const response = await axios.post('http://localhost:8000/auth/2fa', { username, otp });
      alert('Login successful: ' + response.data.token);
    } catch (error) {
      alert('OTP failed');
    }
  };

  return (
    <div>
      {step === 'login' ? (
        <>
          <TextField label="Username" value={username} onChange={(e) => setUsername(e.target.value)} />
          <TextField label="Password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
          <Button onClick={handleLogin}>Login</Button>
        </>
      ) : (
        <>
          <OtpInput value={otp} onChange={setOtp} numInputs={6} renderInput={(props) => <input {...props} />} />
          <Button onClick={handleOtp}>Verify OTP</Button>
        </>
      )}
    </div>
  );
};

export default Login;
```

### 6.- Ejecutar el Front-end:
```console
npm start
```

Abre http://localhost:3000/login en Chrome y prueba el login (usa "admin" y "admin123", luego genera el OTP con pyotp en la consola de Python).

## Paso 5: Integrar con la VM Debian 12
1.- Obtener la IP de la VM:
En la VM:
```console
ip addr
```
Busca la IP (por ejemplo, 192.168.1.x).

### 2.- Configurar PostgreSQL para acceso externo:
Edita /etc/postgresql/15/main/postgresql.conf:
```console
listen_addresses = '*'
```
Edita /etc/postgresql/15/main/pg_hba.conf:
```console
host all all 0.0.0.0/0 md5
```
Reinicia:
```console
systemctl restart postgresql
```

### 3.- Actualizar la conexión en FastAPI:
En backend/database.py, usa la IP de la VM:
```console
DATABASE_URL = "postgresql://<usuario>:<contraseña>@192.168.1.x:5432/ring2all"
```

### 4.- Probar la integración:
Reinicia FastAPI y accede a http://localhost:8000/dialplan en Postman para ver los datos de la base de datos.

Verificación final
Back-end: Corre en http://localhost:8000 y muestra datos de PostgreSQL.
Front-end: Corre en http://localhost:3000 con un menú lateral y login funcional.
VM: FreeSWITCH y PostgreSQL accesibles desde Windows.


# Usar Visual Studio Code (VSCode)
Usar Visual Studio Code (VSCode) es una excelente elección para desarrollar tu proyecto. Vamos a resolver tus dos preguntas: cómo cargar el entorno virtual en la terminal de VSCode y cómo ejecutar el Back-end (FastAPI) y el Front-end (React) al mismo tiempo desde VSCode. Te guiaré paso a paso.

## 1. Cargar el entorno virtual en la terminal de VSCode
VSCode tiene una terminal integrada que puedes configurar para usar tu entorno virtual automáticamente. Aquí te explico cómo hacerlo:

### Paso 1: Abrir VSCode y el proyecto
1.- Abre VSCode.
2.- Haz clic en File > Open Folder y selecciona la carpeta raíz de tu proyecto (D:\freeswitch_admin).
3.- VSCode cargará la estructura del proyecto (backend/ y frontend/).

### Paso 2: Configurar el entorno virtual
1.- Asegúrate de que el entorno virtual existe:
- Deberías tener una carpeta venv en D:\freeswitch_admin\backend si ya la creaste con python -m venv venv.

2.- Abre la terminal integrada en VSCode:
- Haz clic en Terminal > New Terminal (o presiona `Ctrl+``).
- Por defecto, se abrirá una terminal (PowerShell o CMD) en el directorio raíz (D:\freeswitch_admin).

3.- Activa el entorno virtual manualmente:
- Navega al directorio del Back-end:
```console
cd backend
```

- Activa el entorno virtual:
```console
.\venv\Scripts\Activate.ps1
```
- Verás (venv) en la terminal, indicando que el entorno está activo.

4.- Configura VSCode para seleccionar el intérprete automáticamente:
- Presiona Ctrl+Shift+P para abrir la paleta de comandos.
- Escribe y selecciona Python: Select Interpreter.
- Elige el intérprete dentro de tu entorno virtual (por ejemplo, D:\freeswitch_admin\backend\venv\Scripts\python.exe).
- VSCode detectará este entorno y lo usará por defecto.

5.- Automatiza la activación en la terminal:
- Cada vez que abras una nueva terminal en VSCode con el proyecto cargado, ejecuta:
powershell
```console
D:\freeswitch_admin\backend\venv\Scripts\Activate.ps1
```

5.1.- Para hacerlo automático:
 -Haz clic en la flecha junto al botón + en la terminal y selecciona "Configure Terminal Settings".
- Agrega un perfil personalizado en settings.json:
-- Presiona Ctrl+, para abrir Configuración.
-- Busca terminal.integrated.profiles.windows.
-- Edita el archivo settings.json (haz clic en el ícono de lápiz en la esquina superior derecha):
```console
{
    "terminal.integrated.profiles.windows": {
        "PowerShell": {
            "source": "PowerShell",
            "args": ["-NoExit", "-Command", "D:\\freeswitch_admin\\backend\\venv\\Scripts\\Activate.ps1"]
        }
    },
    "terminal.integrated.defaultProfile.windows": "PowerShell"
}
```
- Guarda el archivo. Ahora, cada nueva terminal se abrirá con el entorno virtual activado automáticamente.

### Verificación
- En la terminal de VSCode, escribe:
```console
pip list
```
-Deberías ver fastapi, uvicorn, y las otras dependencias instaladas en el entorno virtual.

## 2. Ejecutar el Back-end y el Front-end al mismo tiempo
Para desarrollar y probar el Back-end (FastAPI) y el Front-end (React) simultáneamente en VSCode, necesitas ejecutar ambos en terminales separadas. VSCode te permite abrir múltiples terminales y configurar tareas para automatizar esto. Aquí te explico cómo hacerlo:

### Opción 1: Usar múltiples terminales manualmente
1.- Abre dos terminales en VSCode:
- Haz clic en Terminal > New Terminal para la primera terminal.
- Haz clic en el ícono + en la barra de terminales para abrir una segunda terminal.

2.- Ejecuta el Back-end en la primera terminal:
- Navega al directorio del Back-end y activa el entorno:
```console
cd D:\freeswitch_admin\backend
.\venv\Scripts\Activate.ps1
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

3.- Ejecuta el Front-end en la segunda terminal:
Navega al directorio del Front-end:
```console
cd D:\freeswitch_admin\frontend
npm start
```
- Esto abrirá automáticamente http://localhost:3000 en tu navegador.

4.- Resultado:
- El Back-end correrá en http://localhost:8000.
- El Front-end correrá en http://localhost:3000.
- Ambos estarán activos al mismo tiempo.

#### Opción 2: Configurar tareas en VSCode para automatizar
1.- Crea un archivo tasks.json:
- Presiona Ctrl+Shift+P, escribe y selecciona Tasks: Configure Tasks.
- Selecciona Create tasks.json file from template > Others.
- Edita tasks.json en .vscode/tasks.json:
```console
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Run Backend",
            "type": "shell",
            "command": "D:\\freeswitch_admin\\backend\\venv\\Scripts\\Activate.ps1 && cd D:\\freeswitch_admin\\backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000",
            "group": "build",
            "presentation": {
                "reveal": "always",
                "panel": "dedicated"
            }
        },
        {
            "label": "Run Frontend",
            "type": "shell",
            "command": "cd D:\\freeswitch_admin\\frontend && npm start",
            "group": "build",
            "presentation": {
                "reveal": "always",
                "panel": "dedicated"
            }
        },
        {
            "label": "Run All",
            "dependsOn": ["Run Backend", "Run Frontend"],
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
```

2.- Ejecuta las tareas:
- Presiona Ctrl+Shift+P, escribe y selecciona Tasks: Run Task.
- Elige Run All para iniciar ambos al mismo tiempo.
- VSCode abrirá dos terminales dedicadas: una para FastAPI y otra para React.
 
## Opción 3: Usar un script externo (opcional)
- Crea un archivo start_all.ps1 en D:\freeswitch_admin:
```console
# start_all.ps1
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd D:\freeswitch_admin\backend; .\venv\Scripts\Activate.ps1; uvicorn main:app --reload --host 0.0.0.0 --port 8000"
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd D:\freeswitch_admin\frontend; npm start"
```

- Ejecuta desde VSCode o PowerShell:
```console
.\start_all.ps1
```

## Verificación
1.- Back-end:
- Abre http://localhost:8000 en tu navegador o Postman.
- Deberías ver {"message": "Welcome to FreeSWITCH Admin API"}.

2.- Front-end:
- Abre http://localhost:3000 en tu navegador.
- Verás la interfaz con el menú lateral y la página de login.

3.- Ambos corriendo:
- En VSCode, revisa las terminales (o ventanas de PowerShell si usaste el script) para confirmar que FastAPI y React están activos.

### Notas adicionales
- Terminal predeterminada: Si prefieres CMD sobre PowerShell en VSCode:
-- Ctrl+,, busca terminal.integrated.shell.windows, y configura:
```console
"terminal.integrated.defaultProfile.windows": "Command Prompt"
```

- Activa el entorno con venv\Scripts\activate.bat en CMD.
-- Conflictos de puertos: Si algo ya usa el puerto 8000 o 3000, cámbialos (por ejemplo, --port 8001 para FastAPI).
-- Integración: Una vez que ambos corran, ajusta el Front-end para llamar al Back-end (por ejemplo, axios.get('http://localhost:8000/')).


