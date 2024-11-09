import hy
import sys


def client():
    "Run the chatthy client."
    print("Running the client.")
    import chatthy.client.repl
    chatthy.client.repl.run()

def serve():
    "Run the chatthy server."
    print("Starting the server...")
    from fvdb.embeddings import force_import
    force_import()
    from chatthy.server import state
    print(f"Using {state.config_file}, defines {', '.join(state.cfg['providers'])}")
    import chatthy.server.server
    print(f"Listening on {state.cfg['listen']}")
    chatthy.server.server.run()

def run():
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        serve()
    else:
        client()

if __name__ == '__main__':
    run()
