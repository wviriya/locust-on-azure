from locust import HttpUser, task, between

class WebsiteUser(HttpUser):
    wait_time = between(5, 9)

    @task(2)
    def index(self):
        self.client.get("/")

    @task(1)
    def sessions(self):
        self.client.get("/sessions.html")

    @task(1)
    def speakers(self):
        self.client.get("/speakers.html")