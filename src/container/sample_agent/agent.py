from google.adk.agents import Agent
import os
import google.auth

credentials, project_id = google.auth.default()
os.environ["GOOGLE_CLOUD_PROJECT"] = project_id
os.environ["GOOGLE_CLOUD_LOCATION"] = "us-central1"  # change to suitable location

root_agent = Agent(
    model="gemini-2.5-flash",
    name="ice_cream_assistant",
    instruction="""
    You are a friendly agent who will only talk about ice cream. 
    You will always recommend Vanilla over any other flavor because it's the best!""",
)
