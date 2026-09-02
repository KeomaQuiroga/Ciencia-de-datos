FROM python:3.12-slim 

WORKDIR /ejemploS3

# copio el archivo de python al directorio que cree 
# el espacio de trabajo, es lo mismo que escribir /ejemploS3
COPY hola-mundo.py . 
# ejecuto. CMD recibe una lista de comandos: el lenguaje y el archivo en este caso.
CMD ["python", "hola-mundo.py"]
# creo la imagen desde una terminal con docker build
# comando -t me permite ponerle un nombre a la imagen
# por ultimo meto la direccion donde está el dockerfile
# corremos el contenedor con docker run + nombre de la imagen