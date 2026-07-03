# my-sbom-tool — a minimal NON-wrangle BYO SBOM tool image proving wrangle
# PR #676's pluggable-SBOM path. Off the wrangle namespace by construction.
FROM python:3.12-slim@sha256:423ed6ab25b1921a477529254bfeeabf5855151dc2c3141699a1bfc852199fbf
COPY generate_sbom.py /usr/local/bin/generate_sbom.py
RUN chmod +x /usr/local/bin/generate_sbom.py
ENTRYPOINT ["python3", "/usr/local/bin/generate_sbom.py"]
