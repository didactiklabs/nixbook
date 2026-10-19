pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common.functions
import qs.modules.common.utils
import qs.services
import ".."

GCloudApi {
    id: root

    property list<string> pendingStrings
    property bool setupReady: false
    readonly property bool preparationReady: GoogleCloud.tokenReady && setupReady

    function translateStrings(strings: list<string>) {
        GoogleCloud.load();
        root.setupReady = false;
        root.pendingStrings = strings;
        root.state = GCloudApi.State.Preparing;
        root.setupReady = true;
    }

    onPreparationReadyChanged: {
        if (!preparationReady) return;
        root.state = GCloudApi.State.Processing;

        const targetLang = Translation.languageCode;
        const payload = {
            "targetLanguageCode": targetLang,
            "contents": root.pendingStrings,
            "mimeType": "text/plain"
        };

        // print("PENDING STRINGS:", root.pendingStrings)

        // The token and the text go through the environment, never an
        // argument: command lines are readable by any local process
        // (/proc/<pid>/cmdline).
        multiproc.environment = ({
            "GCLOUD_TOKEN": GoogleCloud.token,
            "GCLOUD_PROJECT": GoogleCloud.projectId,
            "GCLOUD_PAYLOAD": JSON.stringify(payload)
        });
        var seq = [];
        seq.push([ //
            "bash", "-c", //
            `curl -sL -X POST \
-H @<(printf 'Authorization: Bearer %s\\nx-goog-user-project: %s\\n' "$GCLOUD_TOKEN" "$GCLOUD_PROJECT") \
-H "Content-Type: application/json" \
--data-binary @<(printf '%s' "$GCLOUD_PAYLOAD") \
"https://translation.googleapis.com/v3/projects/$GCLOUD_PROJECT:translateText"`
        ]);

        seq.push(((out) => {
            root.handleApiOutput(out);
        }));

        multiproc.runSequence(seq);
    }

    MultiTurnProcess {
        id: multiproc
    }
}
