FROM --platform=linux/amd64 python:3.10.18 as build

COPY requirements.txt ./

RUN pip install -r requirements.txt

COPY public ./public

COPY app.py  ./

EXPOSE 8080

CMD [ "python", "app.py"]