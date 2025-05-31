# audiocraft/Dockerfile - Ottimizzato
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04 AS base

# Variabili di build
ARG PYTHON_VERSION=3.10
ARG TORCH_VERSION=2.2.1
ARG CUDA_VERSION=cu121

# Evita prompt interattivi
ENV DEBIAN_FRONTEND=noninteractive \
  PYTHONUNBUFFERED=1 \
  PYTHONDONTWRITEBYTECODE=1 \
  PIP_NO_CACHE_DIR=1 \
  PIP_DISABLE_PIP_VERSION_CHECK=1

# Installa dipendenze di sistema minimali
RUN apt-get update && apt-get install -y --no-install-recommends \
   python${PYTHON_VERSION} \
   python${PYTHON_VERSION}-dev \
   python3-pip \
   ffmpeg \
   sox \
   libsox-fmt-all \
   curl \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/*

# Setup Python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
  && update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1

# Installa PyTorch con CUDA
RUN pip install --no-cache-dir \
   torch==${TORCH_VERSION}+${CUDA_VERSION} \
   torchaudio==${TORCH_VERSION}+${CUDA_VERSION} \
   --index-url https://download.pytorch.org/whl/${CUDA_VERSION}

# Installa Audiocraft e dipendenze
# Assuming requirements-audiocraft.txt will be created by another step or is part of the context.
# For now, we'll use the content from AI-Music-Studio.txt's audiocraft Dockerfile for these deps.
# RUN pip install --no-cache-dir -r /tmp/requirements-audiocraft.txt \
#   && rm /tmp/requirements-audiocraft.txt
COPY scripts/requirements.txt /tmp/requirements-audiocraft.txt
RUN pip install --no-cache-dir -r /tmp/requirements-audiocraft.txt \
   && rm /tmp/requirements-audiocraft.txt

# Crea user non-root
RUN useradd -m -u 1000 -s /bin/bash audiocraft

# Setup directory
WORKDIR /app
RUN mkdir -p /models /data /scripts \
  && chown -R audiocraft:audiocraft /app /models /data /scripts

# Copia scripts ottimizzati
# These scripts will be copied from the main scripts directory in docker-compose.yml volume mount.
# For the Docker image itself, we might want to copy them if they are essential for image build or standalone run.
# COPY --chown=audiocraft:audiocraft scripts/musicgen_stem_optimized.py /scripts/musicgen_stem.py
# COPY --chown=audiocraft:audiocraft scripts/audio_processor.py /scripts/

USER audiocraft

# Pre-cache modello piccolo per startup veloce
RUN python3 -c "from audiocraft.models import MusicGen; MusicGen.get_pretrained('facebook/musicgen-small')" || true

HEALTHCHECK --interval=60s --timeout=30s --start-period=300s --retries=3 \
  CMD python3 -c "import torch; assert torch.cuda.is_available()" || exit 1

CMD ["python3", "/scripts/musicgen_stem.py", "--help"]
