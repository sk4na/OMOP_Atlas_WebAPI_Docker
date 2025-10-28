# 🚀 OMOP-CDM + OHDSI WebAPI + ATLAS + Achilles (Docker en Windows)

Este repositorio contiene un entorno completo de la pila **OHDSI/OMOP** configurado para ejecutarse en **Windows Docker Desktop**.  
Incluye los siguientes componentes:

- 🧱 **OMOP CDM v5.4** en PostgreSQL  
- ⚙️ **WebAPI** de OHDSI configurado automáticamente  
- 🌐 **ATLAS** (interfaz web) conectado al WebAPI  
- 📊 **Achilles** para generar estadísticas descriptivas  
- 🧩 **Seeder** opcional para registrar la fuente en WebAPI  

---

## 📦 Requisitos previos

Antes de comenzar, asegúrate de tener instalado:

1. **[Docker Desktop para Windows](https://www.docker.com/products/docker-desktop/)**  
   - Habilita el **WSL2 backend** (recomendado).  
   - Asigna al menos **4 GB de RAM** y **2 CPU** en *Settings → Resources*.

2. **Git** (para clonar este repositorio).  
   - Descarga desde: https://git-scm.com/download/win  

---

## 📁 Estructura del proyecto

```

OMOP_Atlas_WebAPI_Docker/
├── Achilles.Dockerfile           # Imagen personalizada para correr Achilles
├── Dockerfile                    # Imagen base para la BD OMOP
├── docker-compose.yml            # Definición principal de servicios
├── config-local.js               # Configuración de ATLAS
├── default.conf                  # Configuración de Nginx para ATLAS
├── loadDb.sh                     # Script para cargar el CDM y vocabularios
├── scripts/
│   └── seed-webapi.sh            # Script que inserta la fuente en WebAPI
├── vocab/                        # Carpeta con los vocabularios OHDSI (VOCAB)
└── achilles-output/              # (Se genera automáticamente con los resultados)

````

---

## 🧰 Servicios incluidos

| Servicio        | Puerto local | Descripción |
|-----------------|--------------|--------------|
| `omop54`        | 5432         | Base de datos PostgreSQL con OMOP CDM |
| `webapi`        | 8080         | Backend OHDSI WebAPI |
| `atlas`         | 8081         | Interfaz web ATLAS |
| `webapi-seeder` | —            | Inicializa las fuentes en WebAPI |
| `achilles`      | —            | Genera estadísticas descriptivas (R) |

---

## ⚙️ Instrucciones de uso

### 1️⃣ Clonar el repositorio

```
git clone https://github.com/sk4na/OMOP_Atlas_WebAPI_Docker.git
cd OMOP_Atlas_WebAPI_Docker
````

---

### 2️⃣ Cargar los vocabularios (solo la primera vez)

Copia tus archivos de vocabulario OHDSI (`.csv`) dentro de la carpeta `vocab/`.

> ⚠️ Si usas los vocabularios oficiales de Athena, asegúrate de descomprimirlos aquí.

---

### 3️⃣ Iniciar toda la pila

```
docker compose up -d
```

Esto:

* Iniciará PostgreSQL (`omop54`),
* Esperará a que esté saludable,
* Lanzará WebAPI (`webapi`) y luego ATLAS (`atlas`),
* El entorno quedará completamente operativo.

Para ver el estado:

```
docker ps
```

---

### 4️⃣ Acceder a la interfaz web

* **ATLAS:** [http://localhost:8081](http://localhost:8081)
* **WebAPI (JSON):** [http://localhost:8080/WebAPI](http://localhost:8080/WebAPI)

> Si ATLAS muestra “Application initialization failed”, asegúrate de ejecutar el seeder una vez.

---

Verifica:
[http://localhost:8080/WebAPI/source/sources](http://localhost:8080/WebAPI/source/sources)

Deberías ver algo como:

```json
[
  {
    "sourceId": 1,
    "sourceName": "OMOP54 (Postgres)",
    "sourceKey": "OMOP54",
    "daimons": [...]
  }
]
```

---

### 6️⃣ (Opcional) Ejecutar **Achilles**

Cuando tu base OMOP tenga datos reales, ejecuta Achilles para generar estadísticas.

```
docker compose --profile achilles run --rm achilles
```

Los resultados se almacenan en la carpeta `achilles-output/`.

---

### Detener el entorno

```
docker compose down
```

Para borrar también los volúmenes (base de datos, etc.):

```
docker compose down -v
```

---

## 🧩 Personalización

* Modifica `loadDb.sh` si deseas importar tus propios datos CDM.
* Ajusta los nombres de esquemas (`cdm`, `results`, `temp`, `webapi`) dentro de `docker-compose.yml`.
* Puedes aumentar los tiempos de `healthcheck` si tu base tarda en iniciarse (útil en PCs lentos).

---

## 💡 Consejos útiles

* Para revisar los logs:

  ```
  docker compose logs -f webapi
  ```
* Si WebAPI reinicia constantemente, probablemente no logra conectar a PostgreSQL.

---

## 🧑‍💻 Créditos

Proyecto basado en la pila **OHDSI**:

* [OHDSI/WebAPI](https://github.com/OHDSI/WebAPI)
* [OHDSI/Atlas](https://github.com/OHDSI/Atlas)
* [OHDSI/Achilles](https://github.com/OHDSI/Achilles)

Configurado y documentado por **[@sk4na](https://github.com/sk4na)**.

---

## 🧹 Limpieza total

Si quieres eliminar todos los contenedores, volúmenes e imágenes asociados:

```
docker compose down -v --rmi all
docker system prune -af
```

---

