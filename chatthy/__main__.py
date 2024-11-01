import hy
import sys


def client():
    "Run the chatthy client."
    print("Running the client.")
    import chatthy.client.repl
    chatthy.client.repl.run()

def serve():
    "Run the chatthy server."
    print("Running the server.")
    import chatthy.server.server
    chatthy.server.server.run()

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        serve()
    else:
        client()

